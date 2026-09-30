# Garrix Offre

Plateforme personnelle de recherche d'offres d'emploi / missions freelance et de gestion de
candidatures.

| Dossier | Contenu |
|---|---|
| [`backend/`](backend/README.md) | API FastAPI, worker Celery, PostgreSQL, Redis, n8n, Docker — **voir son README** |
| [`backend/docs/DEPLOYMENT.md`](backend/docs/DEPLOYMENT.md) | Déploiement sur le VPS et CI/CD GitHub Actions |
| [`job_automation_uml/`](job_automation_uml/README.md) | Diagrammes UML et règles de gestion (RG-01 à RG-20) |
| `.github/workflows/` | CI/CD : lint, tests, image Docker, déploiement |

L'application mobile Flutter est développée séparément et consomme l'API (`/docs`).
