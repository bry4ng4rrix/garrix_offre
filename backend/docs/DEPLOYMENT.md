# Déploiement (VPS) et CI/CD GitHub Actions

## Architecture en production

```
Internet ──▶ api :8000                 worker Celery (pas de port)
Internet ──▶ n8n :5678 (après création de son compte propriétaire, sinon 127.0.0.1)
             PostgreSQL :5433 et Redis :6380 → 127.0.0.1 uniquement
```

- Pas de reverse proxy : chaque service est joignable directement sur **son propre port**
  (nginx existe encore dans `docker-compose.yml` mais il est désactivé, profil `proxy`).
- `docker-compose.prod.yml` (surcharge) : n8n n'est public que si `N8N_BIND_ADDRESS=0.0.0.0`
  dans le `.env` du serveur.
- `.env` du serveur : `APP_ENV=production`, `LOG_FORMAT=json`, `ALLOW_REGISTRATION=false`,
  secrets générés sur le serveur (jamais copiés depuis un poste de développement).
- Serveur actuel : `allsafe@185.215.167.79`, dossier `~/garrix-offre`.

## Ports

| Port | Écoute sur | Service | Accès |
|---|---|---|---|
| 8000 | toutes les interfaces | API | **public** : `http://185.215.167.79:8000/docs` |
| 5678 | 127.0.0.1, puis toutes les interfaces | n8n | tunnel SSH, puis `http://185.215.167.79:5678` |
| 5433 | 127.0.0.1 | PostgreSQL | serveur uniquement (ou tunnel SSH) |
| 6380 | 127.0.0.1 | Redis | serveur uniquement (ou tunnel SSH) |

Le port 80 n'est plus utilisé par Garrix Offre. Les ports 3000, 3010, 8010 et 9001-9010 du VPS
appartiennent à d'autres applications (`smart_*`, `beszel-agent`) : ne pas les utiliser. Pour
changer un port, modifiez `API_PORT`, `N8N_PORT`, `POSTGRES_PORT` ou `REDIS_PORT` dans le `.env`
du serveur (et la variable GitHub `API_PORT` pour la vérification de la CI).

PostgreSQL et Redis ne sont jamais publiés sur Internet (Redis n'a pas de mot de passe) : pour
un outil comme DBeaver, utilisez un tunnel SSH
(`ssh -i ~/.ssh/garrix_offre_deploy -L 5433:127.0.0.1:5433 allsafe@185.215.167.79`).

URL de l'API : `http://185.215.167.79:8000/` (accueil), `/docs` (Swagger), `/health`, `/ready`,
`/api/v1/...`, WebSocket `ws://185.215.167.79:8000/api/v1/ws`.

## Premier déploiement (déjà effectué)

```bash
cd backend
VPS_HOST=185.215.167.79 VPS_USER=allsafe SSH_KEY=~/.ssh/garrix_offre_deploy scripts/deploy.sh
```

`scripts/deploy.sh` copie le code (sans `.env`, `.venv`, `storage`), crée le `.env` de production
au premier passage, lance `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
--build --wait`, importe les workflows n8n (premier passage, ou `IMPORT_N8N_WORKFLOWS=true`)
et vérifie `/ready`.

## Après le premier déploiement (à faire une fois)

1. **Créer votre compte administrateur** (les inscriptions publiques sont fermées) :
   ```bash
   ssh -i ~/.ssh/garrix_offre_deploy allsafe@185.215.167.79
   cd garrix-offre
   docker compose exec api python -m scripts.create_admin --email vous@exemple.com
   ```
   Le mot de passe est demandé au clavier. Voir [Créer des utilisateurs](#créer-des-utilisateurs)
   pour les comptes suivants.
2. **Configurer n8n.** Tant que son compte propriétaire n'existe pas, n8n n'écoute que sur
   `127.0.0.1` (sinon le premier visiteur pourrait le créer). Passez par un tunnel SSH :
   ```bash
   ssh -i ~/.ssh/garrix_offre_deploy -L 5678:127.0.0.1:5678 allsafe@185.215.167.79
   ```
   Ouvrez http://localhost:5678, créez le compte propriétaire, les credentials Telegram / SMTP /
   IMAP, puis activez les workflows. Ensuite, pour ouvrir n8n sur `http://185.215.167.79:5678` :
   `N8N_BIND_ADDRESS=0.0.0.0` dans `~/garrix-offre/.env`, puis `dc up -d`.
3. **Compléter le `.env` du serveur** (`nano ~/garrix-offre/.env`) : Telegram, SMTP, clés des
   API d'offres (`FRANCE_TRAVAIL_*`, `SOURCE_*`), IA. Puis :
   `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d`.
4. **Sécurité** : changez le mot de passe du compte `allsafe` (`passwd`), puis désactivez
   l'authentification SSH par mot de passe si seules des clés sont utilisées.
5. **HTTPS (recommandé avant d'utiliser l'application mobile)** : faites pointer un nom de domaine
   vers le serveur, puis ajoutez un certificat (Certbot, ou Caddy / Traefik en frontal). Sans
   HTTPS, les tokens circulent en clair sur le réseau.

## CI/CD GitHub Actions

Le workflow `.github/workflows/backend.yml` (à la racine du dépôt) :

| Job | Quand | Rôle |
|---|---|---|
| `quality` | push et pull request | Ruff, Black, MyPy, pytest (PostgreSQL 17 et Redis en services) |
| `docker` | push et pull request | construction de l'image de production |
| `deploy` | push sur `main` (ou lancement manuel) | `scripts/deploy.sh` vers le VPS, puis vérification de `/ready` |

### Secrets à créer

GitHub → dépôt → **Settings → Secrets and variables → Actions → New repository secret** :

| Nom | Valeur |
|---|---|
| `VPS_HOST` | `185.215.167.79` |
| `VPS_USER` | `allsafe` |
| `VPS_SSH_KEY` | contenu **complet** de la clé privée `~/.ssh/garrix_offre_deploy` (de `-----BEGIN OPENSSH PRIVATE KEY-----` à `-----END OPENSSH PRIVATE KEY-----`) : `cat ~/.ssh/garrix_offre_deploy` |
| `VPS_KNOWN_HOSTS` | `185.215.167.79 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN9TJehy4dCeucS45PxCCaek/kbPo/pxwnjLCUclkCJb` |

`VPS_KNOWN_HOSTS` empêche une usurpation du serveur (vérifiable avec
`ssh-keyscan -t ed25519 185.215.167.79`).

### Variables optionnelles

**Settings → Secrets and variables → Actions → onglet Variables** :

| Nom | Défaut | Rôle |
|---|---|---|
| `VPS_PATH` | `garrix-offre` | dossier du projet sur le serveur (relatif au dossier personnel) |
| `API_PORT` | `8000` | port public de l'API, vérifié après le déploiement |

### Environnement

Le job `deploy` utilise l'environnement GitHub `production` (créé automatiquement). Dans
**Settings → Environments → production**, vous pouvez exiger une validation manuelle avant
chaque déploiement (*Required reviewers*).

Aucun secret applicatif (JWT, base de données, Telegram, SMTP...) n'est stocké dans GitHub :
ils restent uniquement dans le `.env` du serveur.

## Démarrer, arrêter, surveiller

Les conteneurs redémarrent seuls après un reboot du VPS (`restart: unless-stopped`, service
Docker activé). Chaque push sur `main` redéploie automatiquement. À la main :

```bash
ssh -i ~/.ssh/garrix_offre_deploy allsafe@185.215.167.79
cd ~/garrix-offre
alias dc='docker compose -f docker-compose.yml -f docker-compose.prod.yml'   # toujours les 2 fichiers

dc up -d                           # démarrer (ou appliquer une modification du .env)
dc ps                              # état et healthchecks (tout doit être "healthy")
dc logs -f api worker              # logs (JSON) ; Ctrl+C pour quitter
dc restart api                     # redémarrer un service (sans relire le .env)
dc stop                            # arrêter sans supprimer
dc down                            # arrêter et supprimer les conteneurs (les données restent)
dc exec postgres pg_dump -U garrix garrix_offre > sauvegarde.sql   # sauvegarde
```

`dc up -d` sans `-f docker-compose.prod.yml` publierait n8n sur Internet même sans compte
propriétaire : utilisez toujours l'alias. Ne lancez jamais `dc down -v` (supprime les volumes, donc la base).

## Créer des utilisateurs

Les inscriptions publiques sont fermées (`ALLOW_REGISTRATION=false`). Trois possibilités :

1. **Ligne de commande sur le serveur** (mot de passe demandé au clavier) :
   ```bash
   dc exec api python -m scripts.create_admin --email vous@exemple.com         # administrateur
   dc exec api python -m scripts.create_user --email collegue@exemple.com      # utilisateur simple
   dc exec api python -m scripts.create_user --email collegue@exemple.com --admin
   ```
   Sur un compte existant, le script remplace le mot de passe et réactive le compte
   (pratique en cas d'oubli).
2. **API, en tant qu'administrateur** (Swagger `http://185.215.167.79:8000/docs` ou l'app Flutter) :
   `POST /api/v1/auth/login` → bouton **Authorize** → `POST /api/v1/users`
   avec `{"email": "...", "password": "...", "is_superuser": false}`.
   `GET /api/v1/users` liste les comptes, `PATCH /api/v1/users/{id}` active/désactive ou
   promeut un compte.
3. **Ouvrir temporairement les inscriptions** : `ALLOW_REGISTRATION=true` dans le `.env`,
   `dc up -d`, inscription via `POST /api/v1/auth/register`, puis remettre `false` et `dc up -d`.

Mot de passe : 8 caractères minimum, au moins une lettre et un chiffre.
