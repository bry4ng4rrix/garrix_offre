from typing import Any

from fastapi import APIRouter, Request

from app.api.dependencies import CurrentUser, DbSession, SuperUser
from app.modules.monitoring.service import MonitoringService
from app.shared.schemas import ApiResponse, error_responses, ok

router = APIRouter(prefix="/monitoring", tags=["Monitoring"])


@router.get(
    "/overview",
    response_model=ApiResponse[dict[str, Any]],
    summary="Vue d'ensemble",
    description="Offres trouvées / nouvelles / analysées aujourd'hui, offres correspondantes, "
    "candidatures, réponses, erreurs de collecte, dernières exécutions n8n, état des services.",
    responses=error_responses(401),
)
def overview(user: CurrentUser, session: DbSession):
    return ok(MonitoringService(session).overview(user))


@router.get(
    "/scraping",
    response_model=ApiResponse[dict[str, Any]],
    summary="Collectes : état des sources et historique (admin)",
    responses=error_responses(401, 403),
)
def scraping(_admin: SuperUser, session: DbSession):
    return ok(MonitoringService(session).scraping())


@router.get(
    "/applications",
    response_model=ApiResponse[dict[str, Any]],
    summary="Statistiques de mes candidatures",
    description="Répartition par statut, taux de réponse, délai moyen de réponse, envois par semaine.",
    responses=error_responses(401),
)
def applications(user: CurrentUser, session: DbSession):
    return ok(MonitoringService(session).applications(user))


@router.get(
    "/system",
    response_model=ApiResponse[dict[str, Any]],
    summary="État du système (admin)",
    description="PostgreSQL, Redis, worker Celery, n8n (avec latence), taille base et stockage.",
    responses=error_responses(401, 403),
)
def system(_admin: SuperUser, session: DbSession, request: Request):
    manager = getattr(request.app.state, "ws_manager", None)
    connections = manager.connection_count if manager else 0
    return ok(MonitoringService(session).system(connections))
