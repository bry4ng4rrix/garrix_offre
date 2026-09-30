"""Sondes de santé (hors /api/v1, utilisées par Docker et les outils de supervision).

- GET /health : l'API répond (liveness). Toujours 200 si le processus tourne ;
  le détail indique l'état de PostgreSQL et Redis.
- GET /ready  : l'API peut servir des requêtes (readiness). 503 si PostgreSQL ou Redis est KO.
"""

import time

from fastapi import APIRouter
from fastapi.responses import JSONResponse

from app.core.config import get_settings
from app.core.database import ping_database
from app.core.redis import ping_redis

router = APIRouter(tags=["Health"])

_STARTED_AT = time.monotonic()


def service_checks() -> dict[str, str]:
    return {
        "api": "ok",
        "postgres": "ok" if ping_database() else "error",
        "redis": "ok" if ping_redis() else "error",
    }


@router.get("/", summary="Accueil de l'API")
def root() -> dict[str, str]:
    settings = get_settings()
    return {
        "name": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "docs": "/docs",
        "health": "/health",
    }


@router.get("/health", summary="Liveness : l'API répond")
def health() -> dict[str, object]:
    checks = service_checks()
    overall = "ok" if all(value == "ok" for value in checks.values()) else "degraded"
    settings = get_settings()
    return {
        "status": overall,
        "version": settings.APP_VERSION,
        "environment": settings.APP_ENV,
        "uptime_seconds": int(time.monotonic() - _STARTED_AT),
        "checks": checks,
    }


@router.get(
    "/ready",
    summary="Readiness : PostgreSQL et Redis sont joignables",
    responses={503: {"description": "Une dépendance est indisponible"}},
)
def ready() -> JSONResponse:
    checks = service_checks()
    is_ready = all(value == "ok" for value in checks.values())
    return JSONResponse(
        status_code=200 if is_ready else 503,
        content={"status": "ready" if is_ready else "not_ready", "checks": checks},
    )
