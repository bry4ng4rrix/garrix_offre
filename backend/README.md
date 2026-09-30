# Garrix Offre — Backend

Backend de recherche d'offres d'emploi / missions freelance et de gestion de candidatures.
Il est consommé par une application **Flutter** (développée séparément) et orchestré par **n8n**.

```
Flutter ──REST/WebSocket──▶ FastAPI ──▶ PostgreSQL (données)
                              │   ├──▶ Redis (rate limit, événements temps réel, file Celery)
                              │   ├──▶ Worker Celery (collectes, matching, envois Telegram/Email)
                              │   └──▶ Stockage fichiers (CV, photos)
n8n (planification, emails) ──webhooks──▶ FastAPI
```

| Composant | Rôle |
|---|---|
| **FastAPI** | API, logique métier, sécurité : c'est la **source de vérité** |
| **PostgreSQL** | Données persistantes |
| **Redis** | Rate limiting, révocation des tokens, bus d'événements temps réel, broker Celery |
| **Worker Celery** | Tâches longues : collecte d'une source, recalcul du matching, envoi des notifications |
| **n8n** | Orchestration : planifie les collectes, lit les emails, envoie des alertes. Aucune règle métier |
| **Adapters de collecte** | Récupèrent les offres des sources autorisées (API, RSS, HTML autorisé) |
| **AIService** | Analyse / rédaction (optionnel : tout fonctionne sans IA) |
| **NotificationService** | Notifications en base + WebSocket + Telegram / Email |
| **StorageService** | Fichiers privés (local aujourd'hui, S3/MinIO possible) |

---

## Sommaire

1. [Démarrage rapide](#1-démarrage-rapide)
2. [Architecture du code](#2-architecture-du-code)
3. [Variables d'environnement](#3-variables-denvironnement)
4. [Docker](#4-docker)
5. [Migrations](#5-migrations)
6. [Lancement local (sans Docker pour l'API)](#6-lancement-local)
7. [Tests et qualité](#7-tests-et-qualité)
8. [API](#8-api)
9. [Sources d'offres](#9-sources-doffres)
10. [n8n](#10-n8n)
11. [Telegram](#11-telegram)
12. [Email](#12-email)
13. [IA (optionnelle)](#13-ia-optionnelle)
14. [Structure des dossiers](#14-structure-des-dossiers)
15. [Ajouter une nouvelle source](#15-ajouter-une-nouvelle-source)
16. [Ajouter un nouveau module](#16-ajouter-un-nouveau-module)
17. [Modifier le scoring](#17-modifier-le-scoring)
18. [Ajouter une nouvelle notification](#18-ajouter-une-nouvelle-notification)
19. [Sécurité](#19-sécurité)
20. [Déploiement sur un VPS et CI/CD](#20-déploiement-sur-un-vps-et-cicd)
21. [Choix techniques](#21-choix-techniques)
22. [Dépannage](#22-dépannage)

---

## 1. Démarrage rapide

Prérequis : Docker 24+ avec Docker Compose v2, `make`.

```bash
cd backend
make env                 # crée .env avec des secrets aléatoires (une seule fois)
docker compose up -d     # construit l'image et démarre toute la stack
docker compose ps        # tous les services doivent être "healthy"
```

| Service | URL |
|---|---|
| API | http://localhost:8000 |
| Swagger (documentation interactive) | http://localhost:8000/docs |
| ReDoc | http://localhost:8000/redoc |
| Santé | http://localhost:8000/health et http://localhost:8000/ready |
| n8n | http://localhost:5678 |
| Reverse proxy nginx | http://localhost:8080 |
| PostgreSQL | `127.0.0.1:5433` (variable `POSTGRES_PORT`) |
| Redis | `127.0.0.1:6380` (variable `REDIS_PORT`) |

Ensuite :

1. Créez **votre** compte : `POST /api/v1/auth/register` (Swagger → *Try it out*).
   **Le premier compte créé devient administrateur.** Mettez ensuite `ALLOW_REGISTRATION=false`.
2. Connectez-vous : `POST /api/v1/auth/login`, copiez `access_token`, bouton **Authorize** de Swagger.
3. Importez les workflows n8n : `make n8n-import` (voir [n8n](#10-n8n)).
4. Optionnel : données de démonstration (`make seed-dev` en local) — compte `demo@example.com`.

---

## 2. Architecture du code

Chaque module métier (`app/modules/<module>/`) a la même organisation :

| Fichier | Responsabilité |
|---|---|
| `router.py` | HTTP uniquement : paramètres, codes de retour, documentation OpenAPI |
| `schemas.py` | Validation des entrées / sorties (Pydantic) |
| `models.py` | Tables SQLAlchemy |
| `repository.py` | Requêtes PostgreSQL (jamais de `commit`) |
| `service.py` | Logique métier (c'est le service qui fait `commit`) |
| `dependencies.py` | Dépendances FastAPI du module |

Règles : pas de SQL ni de logique métier dans les routers ; les modules communiquent par
leurs services/repositories ; n8n, collecte, matching et utilisateurs restent séparés.

Le **pipeline d'une offre** (RG-08) est le même quelle que soit son origine (collecte, n8n, saisie manuelle) :

```
SOURCE → FETCH → PARSE → NORMALIZE → VALIDATE → DEDUPLICATE → SAVE → MATCH → NOTIFY
         scraper.py  parser.py  normalizer.py  validator.py  deduplication.py  pipeline.py
```

- `modules/scraping/scraper.py` (`ScraperService`) : prépare l'adapter et récupère les données brutes ;
- `parser.py` (`ParserService`) : découpe en offres au format commun `JobPayload` ;
- `normalizer.py` (`NormalizerService`) : contrat, lieu, télétravail, salaire, niveau, compétences, langues ;
- `validator.py` : offre invalide = rejetée ; incomplète = enregistrée avec le statut `new` ;
- `deduplication.py` (`DeduplicationService`) : id externe → URL normalisée → empreinte → titre similaire ;
- `pipeline.py` (`JobIngestionService`) : enregistre, calcule le matching, notifie.

Cycles de vie (diagrammes UML du dossier `job_automation_uml/`) :

- **Offre** : `new` (incomplète) → `active` → `expired` → `archived` ; « ignorée » est propre à chaque utilisateur.
- **Candidature** : `not_applied → preparing → ready → submitted → follow_up → interview → offer`,
  `rejected` / `withdrawn` terminaux. `submitted` uniquement via `POST /applications/{id}/submit`
  avec `confirm=true` : **aucune candidature n'est envoyée sans validation explicite**.
  Transitions : `app/modules/applications/rules.py`.
- **Collecte** : `pending → running → success | partial_success | failed`, ou `cancelled`.

---

## 3. Variables d'environnement

Toutes sont décrites dans [`.env.example`](.env.example). `make env` crée `.env` (jamais commité).

| Variable | Rôle |
|---|---|
| `APP_ENV`, `DEBUG`, `LOG_LEVEL`, `LOG_FORMAT` | Environnement et logs (`json` en production) |
| `CORS_ORIGINS` | Origines autorisées (séparées par des virgules) |
| `ALLOW_REGISTRATION` | `false` après la création de votre compte |
| `POSTGRES_*`, `DATABASE_URL` | Base de données (Docker remplace l'hôte par `postgres`) |
| `REDIS_URL`, `CELERY_BROKER_URL` | Redis (bases 0 et 1) |
| `JWT_SECRET_KEY`, `JWT_ACCESS_TOKEN_EXPIRE_MINUTES`, `JWT_REFRESH_TOKEN_EXPIRE_DAYS` | Authentification |
| `RATE_LIMIT_*`, `MAX_REQUEST_SIZE_MB`, `MAX_UPLOAD_SIZE_MB` | Protections HTTP |
| `N8N_WEBHOOK_SECRET` | Secret de l'en-tête `X-N8N-Webhook-Secret` |
| `N8N_ENCRYPTION_KEY` | Chiffrement des credentials n8n (ne jamais le changer ensuite) |
| `NOTIFICATION_DELIVERY_MODE` | `backend` (FastAPI envoie Telegram/Email) ou `n8n` |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | Telegram |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM` | Email |
| `STORAGE_PATH` | Dossier des fichiers (volume Docker `storage_data`) |
| `SCRAPER_*`, `ALLOW_PRIVATE_SOURCE_URLS` | Collecte (User-Agent honnête, délais, protection SSRF) |
| `FRANCE_TRAVAIL_CLIENT_ID/SECRET`, `SOURCE_*` | Clés des API d'offres (voir [Sources](#9-sources-doffres)) |
| `MATCHING_*_WEIGHT`, `MATCHING_DEFAULT_THRESHOLD` | Poids et seuil par défaut du matching |
| `AI_PROVIDER`, `AI_API_KEY`, `AI_MODEL` | IA optionnelle |
| `API_PORT`, `N8N_PORT`, `NGINX_PORT`, `POSTGRES_PORT`, `REDIS_PORT` | Ports publiés sur la machine |

Les secrets sont typés `SecretStr` : ils n'apparaissent jamais dans les logs.

---

## 4. Docker

`docker-compose.yml` démarre : `postgres` (17), `redis`, `migrate` (job ponctuel), `api`,
`worker` (Celery), `n8n`, `nginx`. Tous partagent le réseau privé `garrix-offre-network`.

- `migrate` applique les migrations **non destructives** puis charge les référentiels ; `api`
  et `worker` ne démarrent qu'après sa réussite.
- Healthchecks : `pg_isready`, `redis-cli ping`, `/ready` pour l'API, `celery inspect ping`,
  `/healthz` pour n8n. `docker compose up -d --wait` attend qu'ils soient tous verts.
- Volumes : `postgres_data`, `redis_data`, `n8n_data`, `storage_data`.
- PostgreSQL et Redis ne sont publiés que sur `127.0.0.1`.

```bash
make docker-up        # build + démarrage
make docker-ps        # état et healthchecks
make docker-logs      # logs API + worker
make docker-down      # arrêt (les volumes sont conservés)
make dev-docker       # mode développement : hot reload de l'API et du worker, logs lisibles
```

`docker-compose.dev.yml` monte le code source dans les conteneurs (`uvicorn --reload`,
`watchfiles` pour Celery).

---

## 5. Migrations

Alembic, avec des noms de contraintes stables (`app/core/database.py`).

```bash
alembic revision --autogenerate -m "ajout de la colonne X"   # ou : make revision m="..."
alembic upgrade head                                          # ou : make migrate (recommandé)
alembic downgrade -1                                          # ou : make downgrade
```

`make migrate` (`scripts/migrate.py`, utilisé par Docker) **refuse** une migration destructive
(`op.drop_table`, `op.drop_column`, `DROP`, `TRUNCATE`, `DELETE FROM`, ou `destructive = True`
dans le fichier). Après une sauvegarde, pour l'appliquer volontairement :
`ALLOW_DESTRUCTIVE_MIGRATIONS=true make migrate`.

Toujours relire une migration générée. Le test `tests/unit/test_migrations_guard.py` vérifie
que les migrations existantes ne sont pas destructives, et la suite de tests crée son schéma
avec ces mêmes migrations.

---

## 6. Lancement local

Pour développer l'API hors Docker (PostgreSQL et Redis restent dans Docker) :

```bash
make install     # .venv Python 3.12 + dépendances de dev (uv ou pip)
make env         # si ce n'est pas déjà fait
make migrate     # schéma + référentiels
make seed-dev    # optionnel : compte et offres de démonstration
make dev         # API sur http://localhost:8000 avec rechargement automatique
make worker      # dans un autre terminal : worker Celery
```

---

## 7. Tests et qualité

```bash
make test         # démarre PostgreSQL/Redis (Docker) puis lance pytest
make test-unit    # tests unitaires seuls (aucune base nécessaire)
make test-docker  # tests dans un conteneur
make lint         # Ruff + Black (vérification) + MyPy
make format       # corrections automatiques
```

- `tests/unit/` : scoring, parsing (salaires, lieux...), extraction de compétences, adapters
  (serveur HTTP simulé : robots.txt, 403, CAPTCHA...), validation Pydantic, sécurité, règles de candidature.
- `tests/integration/` : chaque module via l'API, avec un vrai PostgreSQL (base `<nom>_test`,
  recréée par les migrations) et un vrai Redis (base 15). Celery s'exécute en mode *eager*.
- Aucun appel réseau externe : Telegram, SMTP et IA sont simulés.

---

## 8. API

Toutes les routes sont préfixées par `/api/v1`. Documentation complète : `/docs`.

### Format des réponses

```json
{ "success": true, "data": { ... } }
{ "success": true, "data": { "items": [ ... ], "pagination": { "total": 100, "page": 1, "page_size": 20, "pages": 5 } } }
{ "success": false, "error": { "code": "JOB_NOT_FOUND", "message": "Job not found" } }
```

Pagination : `?page=2&page_size=20` ou `?limit=20&offset=20`. Les erreurs de validation
renvoient `VALIDATION_ERROR` avec la liste des champs (sans renvoyer les valeurs reçues).
Aucune trace, requête SQL ni secret n'est jamais renvoyé.

### Authentification

1. `POST /auth/register` → `POST /auth/login` : `access_token` (15 min) + `refresh_token` (30 j).
2. En-tête `Authorization: Bearer <access_token>`.
3. `POST /auth/refresh` : nouveau couple de tokens ; l'ancien refresh token est révoqué
   (réutiliser un token révoqué coupe toutes les sessions).
4. `POST /auth/logout` : révoque immédiatement l'access token et le refresh token.

### Principaux endpoints

| Domaine | Endpoints |
|---|---|
| Auth | `POST /auth/register`, `/login`, `/refresh`, `/logout`, `GET /auth/me` |
| Profil | `GET/PUT /profile`, `POST/GET/DELETE /profile/photo` |
| Compétences | `/skills` (CRUD), `/skills/catalog`, `/skills/categories` |
| Expérience | `/experiences` (parcours), `/experience-preferences` (+ `/grouped`), `/experience-levels` |
| Recherche | `GET/PUT /preferences`, `/job-titles` (CRUD), `/contract-types` (CRUD) |
| Offres | `GET /jobs` (filtres), `POST /jobs`, `GET/PUT/DELETE /jobs/{id}`, `PATCH /jobs/{id}/state`, `GET /jobs/{id}/raw` |
| Matching | `POST /jobs/{id}/match`, `POST /matching/recalculate`, `GET/PUT /matching/settings` |
| Candidatures | `/applications` (CRUD), `PATCH /{id}/status`, `POST /{id}/prepare`, `/generate`, `/submit`, `GET /{id}/history`, `/applications/responses` |
| Documents | `/documents` (upload multipart), `GET /documents/{id}/download` |
| Entreprises / recruteurs | `/companies`, `/recruiters` |
| Sources / collecte | `/sources` (`?category=jobs\|clients\|services`), `POST /sources/{id}/run`, `/test`, `/scraping/runs`, `/scraping/adapters` |
| Notifications | `GET /notifications`, `/unread-count`, `PATCH /{id}/read`, `/read-all`, `/settings` |
| Monitoring | `/monitoring/overview`, `/scraping`, `/applications`, `/system` |
| IA | `GET /ai/status`, `POST /ai/jobs/{id}/analyze` |
| n8n | `/webhooks/n8n/...` (voir [n8n](#10-n8n)) |
| Audit | `GET /audit-logs` (admin) |

Filtres de `GET /jobs` : `search`, `min_score`, `contract_type`, `remote`, `location`, `skill`,
`company`, `experience_level`, `source`, `source_category` (`jobs` = emplois, `clients` =
missions freelance), `status` (`new`, `active`, `expired`, `archived`, `unseen`, `saved`,
`ignored`, `applied`, `all`), `published_after`, `published_before`, `sort_by`
(`published_at`, `created_at`, `score`, `title`), `sort_order`.

Données globales (offres, entreprises, sources, référentiels) : écriture réservée aux
administrateurs. Données personnelles (profil, candidatures, documents, notifications) :
visibles uniquement par leur propriétaire.

### Offre normalisée (extrait)

```json
{
  "id": "…", "title": "Développeur Full Stack Python / React",
  "source": { "name": "Remote OK", "category": "jobs", "url": "https://…", "external_id": "123" },
  "company": { "name": "Tech Solutions", "website": "https://…", "address": { "city": "Paris", "country": "France" }, "contact": { "email": null, "phone": null } },
  "recruiter": { "name": null, "email": null, "contact_source": null },
  "location": { "city": "Paris", "country": "France", "remote": true, "hybrid": false },
  "contract": { "type": "cdi", "work_time": "full_time" },
  "salary": { "min": 35000, "max": 45000, "currency": "EUR", "period": "year" },
  "skills": [ { "name": "Python", "category": "backend", "requirement": "required" } ],
  "matching": { "score": 91, "matched_skills": ["Python"], "missing_skills": [], "reasons": ["…"] },
  "application": { "url": "https://…", "email": null },
  "status": { "state": "active", "is_new": true, "is_expired": false, "is_saved": false, "is_ignored": false, "application_status": "not_applied" }
}
```

### WebSocket

`ws://<hôte>/api/v1/ws?token=<access_token>` (ou en-tête `Authorization`).

- à la connexion : `{"type": "connected", "data": {"unread_notifications": 3}}` ;
- événements : `notification`, `new_job`, `application_status`, `recruiter_response`,
  `scraping_run`, `scraping_error`, `matching_recalculated`, `monitoring` ;
- envoyer `ping` → réponse `{"type": "pong"}` ;
- fermeture code `4001` à l'expiration du token : reconnectez-vous avec un token rafraîchi,
  puis relisez les notifications non lues via REST (`GET /notifications?is_read=false`).

---

## 9. Sources d'offres

Chaque source a une **catégorie** : `jobs` (offres d'emploi), `clients` (missions freelance)
ou `services` (API de données d'offres). Le seed configure les sites demandés ainsi :

**Collecte automatique (accès officiel uniquement)**

| Source | Catégorie | Accès | Par défaut |
|---|---|---|---|
| Remote OK | jobs | API publique officielle (« Remote OK API ») | active |
| We Work Remotely | jobs | Flux RSS publics par catégorie | active |
| Jobgether | jobs | Flux JSON autorisé par son robots.txt | active |
| Codeko.tech | jobs | Flux RSS WordPress des annonces | active |
| France Travail | jobs | API officielle « Offres d'emploi v2 » | à activer après `FRANCE_TRAVAIL_CLIENT_ID/SECRET` |
| Codeur.com | clients | Flux RSS public des projets | active |
| Freelancer.com | clients | API publique officielle | active |
| Adzuna | services | API officielle (clé gratuite) | à activer après `SOURCE_ADZUNA_APP_ID/KEY` |
| Findwork.dev | services | API officielle (clé gratuite) | à activer après `SOURCE_FINDWORK_API_KEY` |
| JobDataLake | services | API officielle (1 000 crédits gratuits) | à activer après `SOURCE_JOBDATALAKE_API_KEY` |
| The Muse | services | API officielle | a répondu 403 sans clé : à tester avec `SOURCE_THE_MUSE_API_KEY` |

**Sans accès automatique autorisé → alertes email (workflow n8n 7) ou ajout manuel**

| Catégorie | Sites | Raison |
|---|---|---|
| jobs | LinkedIn, Indeed, Glassdoor, Welcome to the Jungle, APEC, Monster, Hellowork, Talent.com, Arc.dev, Remote.co | CGU interdisant la collecte, API fermées ou réservées aux partenaires, pas de flux public |
| jobs (Madagascar) | Madajob, Job2Mada | Aucun flux/API détecté : alertes email, ou source HTML si leurs CGU l'autorisent |
| clients | Malt, Upwork, Free-Work, Workana, Jobbers, Guru, Toptal, Crème de la Crème, Sortlist, Work IT Mada | Pas d'API publique, anti-bot, réseaux sur sélection |
| clients | Fiverr, ComeUp | Marketplaces de services : pas d'offres de clients à collecter |
| désactivées | Stack Overflow Jobs (fermé en 2022), GitHub Jobs (fermé en 2021), Jobnet.dk (injoignable) | — |

La raison exacte de chaque source est dans son champ `notes` (visible via `GET /sources`).
Le système **ne contourne jamais** robots.txt, CAPTCHA, authentification ou anti-bot : le client
HTTP (`modules/scraping/http.py`) s'identifie honnêtement, limite son débit, respecte robots.txt,
bloque les adresses internes (SSRF) et **s'arrête** au premier 401/403/429 ou page anti-bot.

**Alertes email** : créez des alertes (avec votre adresse) sur LinkedIn, Indeed, APEC, Malt...,
triez-les dans le dossier IMAP `Alertes-Emploi`. n8n transmet chaque email à
`POST /webhooks/n8n/job-alert-email` : la source est reconnue par le domaine de l'expéditeur,
les offres (titre + lien) sont extraites puis suivent le pipeline. Aucune page du site n'est visitée.

---

## 10. n8n

n8n **orchestre** ; FastAPI garde toute la logique métier. Les workflows sont dans
`n8n/workflows/` :

| Workflow | Déclencheur | Rôle |
|---|---|---|
| 1. Collecte des offres | toutes les 3 h | lit les sources ; `fetch_mode=backend` → FastAPI collecte ; `fetch_mode=n8n` → n8n lit le RSS, normalise, envoie à FastAPI, puis rapporte le bilan |
| 2. Recalcul du matching | 5 h | `POST /webhooks/n8n/matching/recalculate` |
| 3. Envoi des notifications | webhook | utilisé si `NOTIFICATION_DELIVERY_MODE=n8n` : Telegram / Email |
| 4. Relances | 9 h | candidatures sans réponse → statut `follow_up` |
| 5. Réponses des recruteurs | IMAP (dossier `Candidatures`) | `POST /webhooks/n8n/recruiter-response` |
| 6. Monitoring | 15 min / 20 h / 3 h | `/ready` (alerte Telegram directe si KO), rapport quotidien, maintenance (expiration des offres, collectes bloquées) |
| 7. Alertes email | IMAP (dossier `Alertes-Emploi`) | `POST /webhooks/n8n/job-alert-email` |

Mise en route :

1. Ouvrez http://localhost:5678 et créez le compte propriétaire n8n.
2. `make n8n-import` (réimporter met à jour les workflows existants).
3. Dans n8n, créez les credentials **Telegram**, **SMTP** et **IMAP** puis associez-les aux nœuds
   concernés. L'URL de l'API et le secret sont lus dans l'environnement (`$env.GARRIX_API_URL`,
   `$env.N8N_WEBHOOK_SECRET`) : rien n'est écrit dans les workflows.
4. Activez les workflows voulus (chacun a aussi un déclencheur « Lancer manuellement »).

Webhooks exposés par FastAPI (en-tête `X-N8N-Webhook-Secret` obligatoire) :
`POST /job`, `/jobs`, `/job-alert-email`, `/scraping-status`, `/application-status`,
`/recruiter-response`, `/sources/{id}/run`, `/matching/recalculate`, `/maintenance/expire-jobs`,
`/monitoring-alert` ; `GET /sources`, `/applications/follow-ups-due`, `/monitoring/summary`.

**Idempotence (RG-18)** : envoyez `Idempotency-Key` (ex. Message-ID d'un email) ; un second
appel avec la même clé renvoie la réponse enregistrée (en-tête `Idempotent-Replayed: true`).
n8n ne peut jamais passer une candidature à `submitted`.

---

## 11. Telegram

1. Créez un bot avec [@BotFather](https://t.me/BotFather) → `TELEGRAM_BOT_TOKEN`.
2. Écrivez à votre bot, puis ouvrez `https://api.telegram.org/bot<TOKEN>/getUpdates` → `chat.id` → `TELEGRAM_CHAT_ID`.
3. Redémarrez : `docker compose up -d`.

`TelegramService` (`modules/integrations/telegram/service.py`) envoie : nouvelle offre, offre à
fort score, candidature prête, réponse de recruteur, erreur système. Le token n'est jamais loggé.
Le `TELEGRAM_CHAT_ID` du `.env` n'est utilisé que pour les administrateurs ; un autre utilisateur
renseigne son propre `telegram_chat_id` via `PUT /notifications/settings`.

---

## 12. Email

Renseignez `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM`
(`SMTP_USE_TLS=true` pour le port 587, `SMTP_USE_SSL=true` pour le 465).

`EmailService` (`modules/integrations/email/service.py`, gabarits dans `templates.py`) envoie :
nouvelle offre, réponse de recruteur, statut de candidature, erreur. Il envoie aussi l'email de
candidature (avec le CV en pièce jointe) **uniquement** lors d'un `POST /applications/{id}/submit`
avec `confirm=true` et `send_email=true`.

Activez l'email par utilisateur : `PUT /notifications/settings` (`email_enabled`, `external_types`).

---

## 13. IA (optionnelle)

`AIService` (`modules/ai/service.py`) : `analyze_job()`, `extract_skills()`,
`extract_requirements()`, `generate_application()`, `analyze_recruiter_response()`.

- `AI_PROVIDER=none` (défaut) : règles déterministes (`modules/ai/rules.py`).
- `AI_PROVIDER=anthropic` + `AI_API_KEY` : Claude via le SDK officiel (`AI_MODEL` vide =
  `claude-opus-5-5`), sorties JSON structurées, effort `low` pour l'analyse et `medium` pour la
  rédaction, bascule automatique sur un modèle de repli si un filtre refuse une requête légitime.
- En cas d'erreur du fournisseur, les règles prennent le relais (`generated_by: "rules"`).
- Le **matching n'utilise jamais l'IA**. Les contenus externes sont transmis comme données,
  jamais comme instructions.
- Autre fournisseur : créer `providers/<nom>.py` (classe héritant de `AIProvider`), l'ajouter à
  `AI_PROVIDER` et à `get_ai_provider()`.

---

## 14. Structure des dossiers

```
backend/
├── app/
│   ├── main.py                 # création de l'application, middlewares, lifespan
│   ├── worker.py               # application Celery
│   ├── core/                   # config, database, security, redis, logging, exceptions, middlewares
│   ├── api/                    # router principal, dépendances communes, /health, /ready
│   ├── shared/                 # pagination, enums, schémas de réponse, utilitaires, géographie
│   └── modules/
│       ├── auth/ users/ profile/ skills/ experiences/ job_titles/ contract_types/ preferences/
│       ├── companies/ recruiters/ sources/ jobs/ matching/ applications/ documents/
│       ├── scraping/           # adapters/, pipeline (scraper, parser, normalizer, validator, deduplication)
│       ├── notifications/ realtime/ monitoring/ audit/ ai/
│       ├── integrations/       # n8n/, telegram/, email/
│       └── models.py           # import de tous les modèles (Alembic)
├── alembic/                    # migrations
├── scripts/                    # migrate.py, seed.py, generate_env.py
├── tests/                      # unit/ et integration/
├── n8n/workflows/              # workflows importables
├── docker/                     # nginx, init PostgreSQL
├── storage/                    # fichiers (local)
├── Dockerfile, docker-compose.yml, docker-compose.dev.yml, docker-compose.prod.yml
└── Makefile, pyproject.toml, requirements*.txt, .env.example
```

---

## 15. Ajouter une nouvelle source

**Cas 1 — API JSON ou flux RSS : aucune ligne de code.** Créez la source (admin) :

```http
POST /api/v1/sources
{
  "name": "Mon flux",
  "category": "jobs",
  "type": "rss",
  "adapter": "rss_feed",
  "base_url": "https://example.com",
  "scraping_enabled": true,
  "rate_limit": 10,
  "configuration": { "feed_url": "https://example.com/jobs.rss", "title_separator": ":" }
}
```

`GET /scraping/adapters` donne le schéma de configuration de chaque adapter (`json_api` :
`field_map`, `items_path`, `url_template`, `defaults`, `secret_headers`...). Testez sans rien
enregistrer : `POST /sources/{id}/test`, puis lancez : `POST /sources/{id}/run`.
Clé d'API : ajoutez `SOURCE_MA_CLE=...` au `.env` et référencez **son nom** :
`"secret_headers": {"Authorization": "Bearer {SOURCE_MA_CLE}"}` (seules les variables `SOURCE_*`
sont accessibles, et aucune clé n'est stockée en base).

**Cas 2 — nouveau format : écrire un adapter.**

```python
# app/modules/scraping/adapters/mon_site.py
from pydantic import BaseModel, HttpUrl
from app.modules.scraping.base import FetchedPage, SourceAdapter
from app.modules.scraping.registry import register_adapter
from app.shared.enums import SourceType

class MonSiteConfig(BaseModel):
    url: HttpUrl

@register_adapter
class MonSiteAdapter(SourceAdapter):
    key = "mon_site"
    description = "API officielle de Mon Site"
    source_types = frozenset({SourceType.API})
    config_model = MonSiteConfig
    respects_robots_txt = False  # True pour une page HTML ou un flux RSS

    def fetch(self) -> list[FetchedPage]:
        response = self.http.get_text(str(self.config.url))   # client poli (débit, robots, SSRF)
        return [FetchedPage(url=str(self.config.url), content=response.text)]

    def parse(self, page: FetchedPage) -> list[dict]:
        return [{"title": item["title"], "url": item["link"], "company": item["company"]}
                for item in json.loads(page.content)["offers"]]
```

Ajoutez l'import dans `_load_builtin_adapters()` (`scraping/registry.py`) et un test avec
`httpx.MockTransport` (voir `tests/unit/test_adapters.py`). La normalisation, la déduplication,
le matching et les notifications sont automatiques.

**Cas 3 — site sans accès autorisé** : source `type=webhook`, `fetch_mode=n8n`,
`configuration.alert_link_domains=["site.com"]`, puis alertes email.

Page HTML : n'utilisez l'adapter `html_page` que si les CGU l'autorisent (`terms_reviewed=true`).

---

## 16. Ajouter un nouveau module

1. `app/modules/mon_module/` avec `models.py`, `schemas.py`, `repository.py`, `service.py`,
   `router.py`, `dependencies.py` (copiez un module simple comme `job_titles/`).
2. Importez le modèle dans `app/modules/models.py`.
3. Ajoutez le router à `MODULE_ROUTERS` dans `app/api/router.py` et un tag dans `app/main.py`.
4. `make revision m="mon module"`, relisez la migration, `make migrate`.
5. Tests dans `tests/integration/test_mon_module.py`.

---

## 17. Modifier le scoring

- **Poids** (sans code) : `PUT /api/v1/matching/settings` (par utilisateur) ou `MATCHING_*_WEIGHT`
  dans `.env` (valeurs par défaut). Les poids sont relatifs : le score est ramené sur 100 ; `0`
  désactive un critère. Seuil « offre très compatible » : `matching_threshold` dans `PUT /preferences`.
- **Règles** : `app/modules/matching/rules.py` (score d'une donnée inconnue, compétence
  obligatoire ×2, facteur par niveau, plafond si une technologie obligatoire manque, conversion
  des salaires...).
- **Calcul** : `app/modules/matching/scoring.py`, fonctions pures (`score_skills`,
  `score_location`...) assemblées par `compute_match()`. Ajouter un critère = une fonction
  `score_x()` + un poids dans `MatchingWeights` et `MatchingSettings` (+ migration) + des tests
  dans `tests/unit/test_scoring.py`.
- Après modification : `POST /matching/recalculate`.

---

## 18. Ajouter une nouvelle notification

1. Ajoutez la valeur à `NotificationType` (`app/shared/enums.py`) — pas de migration (stockage texte).
2. Au bon endroit du service métier, **après** le commit :
   ```python
   NotificationService(session).notify(user.id, NotificationType.MON_TYPE, "Titre", "Message", data={...})
   ```
   Cela enregistre la notification, publie l'événement WebSocket et planifie l'envoi externe.
3. Mise en forme Telegram / Email : `send_notification()` de `TelegramService` et `EmailService`.
4. Envoi externe par défaut : ajoutez le type à `DEFAULT_EXTERNAL_TYPES` (`notifications/models.py`).

---

## 19. Sécurité

- Mots de passe Argon2 ; access token JWT court + refresh token opaque (haché en base, rotation,
  détection de réutilisation) ; logout immédiat (liste de révocation Redis).
- Rate limiting Redis (global et strict sur l'authentification), limite de taille des requêtes.
- Uploads : extension, MIME déclaré **et** signature réelle du fichier, taille ; fichiers privés
  servis uniquement à leur propriétaire (`nosniff`, `no-store`).
- Webhooks n8n : secret comparé en temps constant, idempotence.
- URLs : `http(s)` uniquement, adresses internes refusées pour la collecte (SSRF).
- Logs JSON sans données sensibles (mots de passe, tokens, clés, token Telegram masqués).
- Erreurs sans trace ni SQL ; journal d'audit des opérations critiques (`GET /audit-logs`).
- Secrets uniquement dans `.env` (`SecretStr`), jamais commité.

---

## 20. Déploiement sur un VPS et CI/CD

Voir [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) : `docker-compose.prod.yml` (seul nginx est
public ; API, n8n, PostgreSQL et Redis restent sur `127.0.0.1`), création du compte
administrateur en ligne de commande, et pipeline GitHub Actions (tests → image → déploiement SSH).

---

## 21. Choix techniques

| Choix | Pourquoi |
|---|---|
| SQLAlchemy **synchrone** (psycopg 3) | plus simple à lire et à déboguer qu'async ; FastAPI exécute les endpoints `def` dans un pool de threads ; même code dans Celery |
| **Celery + Redis** | collectes, recalculs et envois externes hors des requêtes HTTP ; n8n reste le planificateur |
| WebSocket via **Redis pub/sub** | les événements émis par le worker arrivent aux clients connectés à n'importe quel processus API ; `NotificationService` ne connaît pas le WebSocket |
| Énumérations stockées en **texte** | ajouter une valeur ne nécessite pas de migration |
| Référentiels en base (contrats, niveaux, catégories) | modifiables depuis Flutter sans redéploiement (RG-02/03) |
| Premier compte = administrateur | usage personnel, multi-utilisateur possible ensuite |
| Salaire minimum / télétravail stockés dans les préférences | une seule source de vérité, exposée aussi par `/profile` |
| Types de contrat « Part-time / Full-time » conservés | demandés dans le cahier des charges ; le temps de travail est aussi exposé à part (`contract.work_time`) |
| Transitions de candidature ajoutées à l'UML | `READY→PREPARING`, `SUBMITTED→INTERVIEW`, `INTERVIEW→REJECTED/WITHDRAWN`, `OFFER→WITHDRAWN` : cas réels courants |

---

## 22. Dépannage

| Problème | Solution |
|---|---|
| `JWT_SECRET_KEY` / `N8N_WEBHOOK_SECRET` trop courts au démarrage | `make env` ou régénérer les valeurs |
| Port 5433 / 6380 / 8000 déjà utilisé | modifier `POSTGRES_PORT`, `REDIS_PORT`, `API_PORT` dans `.env` |
| `migrate` en échec « Destructive migrations refused » | sauvegarder la base, puis `ALLOW_DESTRUCTIVE_MIGRATIONS=true` (voir §5) |
| Collecte `failed` avec « robots.txt disallows » ou « HTTP 403 » | la source refuse la collecte automatique : utiliser son API officielle ou ses alertes email |
| Pas de notification Telegram | vérifier `TELEGRAM_*`, puis `GET /notifications/settings` (`telegram_configured`) |
| Workflows n8n sans effet | credentials à créer, workflows à activer, `docker compose logs n8n` |
| Passage d'une ancienne version de PostgreSQL | `pg_dump` puis restauration dans le nouveau volume |
