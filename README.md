# Garrix Offre

Plateforme personnelle de recherche d'offres d'emploi / missions freelance et de gestion de
candidatures.

| Dossier | Contenu |
|---|---|
| [`backend/`](backend/README.md) | API FastAPI, worker Celery, PostgreSQL, Redis, n8n, Docker — **voir son README** |
| [`mobile/`](mobile/README.md) | Application Flutter (Android + Linux), thème noir minimaliste — **voir son README** |
| [`backend/docs/DEPLOYMENT.md`](backend/docs/DEPLOYMENT.md) | Déploiement sur le VPS et CI/CD GitHub Actions |
| [`job_automation_uml/`](job_automation_uml/README.md) | Diagrammes UML et règles de gestion (RG-01 à RG-20) |
| `.github/workflows/` | CI/CD du backend : lint, tests, image Docker, déploiement (l'application mobile se construit en local) |

L'application Flutter consomme l'API REST (`/api/v1`, documentée sur `/docs`) et le WebSocket
temps réel (`/api/v1/ws`).
