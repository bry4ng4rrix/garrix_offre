"""Point d'entrée de l'API FastAPI.

Lancement local : uvicorn app.main:app --reload
Documentation   : http://localhost:8000/docs (Swagger) et /redoc
"""

import asyncio
import contextlib
import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

import app.modules.models
from app.api.health import router as health_router
from app.api.router import api_router
from app.core.config import get_settings
from app.core.exceptions import register_exception_handlers
from app.core.logging import setup_logging
from app.core.middleware import (
    BodySizeLimitMiddleware,
    RateLimitMiddleware,
    RequestLoggingMiddleware,
)
from app.core.redis import create_async_redis
from app.modules.realtime.manager import WebSocketManager
from app.modules.realtime.router import router as realtime_router

logger = logging.getLogger("app")

API_DESCRIPTION = """
API de recherche d'offres d'emploi et de gestion de candidatures.

**Authentification** : `POST /api/v1/auth/login` puis bouton *Authorize* avec l'access token.

**Format des réponses** : `{"success": true, "data": ...}` ou
`{"success": false, "error": {"code": "...", "message": "..."}}`.

**Temps réel** : WebSocket `ws://<host>/api/v1/ws?token=<access_token>`.
"""

OPENAPI_TAGS = [
    {"name": "Auth", "description": "Inscription, connexion, tokens JWT"},
    {"name": "Users", "description": "Compte utilisateur et administration"},
    {"name": "Profile", "description": "Profil professionnel et photo"},
    {"name": "Skills", "description": "Compétences du profil et catalogue"},
    {"name": "Experiences", "description": "Parcours, technologies recherchées, niveaux"},
    {"name": "Job Titles", "description": "Postes recherchés"},
    {"name": "Contract Types", "description": "Types de contrat (référentiel dynamique)"},
    {"name": "Preferences", "description": "Préférences de recherche (vue centrale)"},
    {"name": "Companies", "description": "Entreprises"},
    {"name": "Recruiters", "description": "Recruteurs et coordonnées publiques"},
    {"name": "Sources", "description": "Sources d'offres (API, RSS, HTML autorisé...)"},
    {"name": "Scraping", "description": "Collectes et adapters"},
    {"name": "Jobs", "description": "Offres d'emploi normalisées"},
    {"name": "Matching", "description": "Score de correspondance offre / profil"},
    {"name": "Applications", "description": "Candidatures et réponses recruteurs"},
    {"name": "Documents", "description": "CV, lettres, photos (fichiers privés)"},
    {"name": "Notifications", "description": "Notifications et préférences"},
    {"name": "Monitoring", "description": "Statistiques et état des services"},
    {"name": "AI", "description": "Analyse et génération (optionnelle)"},
    {"name": "n8n Webhooks", "description": "Endpoints appelés par n8n (X-N8N-Webhook-Secret)"},
    {"name": "Audit", "description": "Journal des opérations critiques"},
    {"name": "Realtime", "description": "WebSocket"},
    {"name": "Health", "description": "Sondes de santé"},
]


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Démarrage : client Redis async + écoute des événements temps réel."""
    app.state.redis = create_async_redis()
    app.state.ws_manager = WebSocketManager()
    listener = asyncio.create_task(app.state.ws_manager.listen(app.state.redis))
    logger.info("API started", extra={"environment": get_settings().APP_ENV})
    try:
        yield
    finally:
        listener.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await listener
        await app.state.redis.aclose()
        logger.info("API stopped")


def create_app() -> FastAPI:
    settings = get_settings()
    setup_logging(settings)

    app = FastAPI(
        title=settings.APP_NAME,
        version=settings.APP_VERSION,
        description=API_DESCRIPTION,
        openapi_tags=OPENAPI_TAGS,
        lifespan=lifespan,
        docs_url="/docs",
        redoc_url="/redoc",
        debug=settings.DEBUG,
    )
    register_exception_handlers(app)

    # Le dernier middleware ajouté est le plus externe.
    app.add_middleware(BodySizeLimitMiddleware)
    app.add_middleware(RateLimitMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.CORS_ORIGINS,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
        expose_headers=["X-Request-ID"],
    )
    app.add_middleware(RequestLoggingMiddleware)

    app.include_router(health_router)
    app.include_router(api_router, prefix=settings.API_V1_PREFIX)
    app.include_router(realtime_router, prefix=settings.API_V1_PREFIX)
    return app


app = create_app()
