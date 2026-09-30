import logging
import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, status

from app.api.dependencies import CurrentUser, DbSession, SuperUser
from app.core.exceptions import ServiceUnavailableError
from app.modules.scraping.registry import list_adapters
from app.modules.scraping.schemas import (
    AdapterInfo,
    RunRequestResult,
    ScrapingRunRead,
    SourceTestResult,
)
from app.modules.scraping.service import ScrapingService
from app.shared.enums import ScrapingRunStatus, ScrapingTrigger
from app.shared.pagination import Page, PaginationParams, build_page
from app.shared.schemas import ApiResponse, error_responses, ok
from app.shared.utils import utcnow

router = APIRouter(tags=["Scraping"])
logger = logging.getLogger("app.scraping")


def get_scraping_service(session: DbSession) -> ScrapingService:
    return ScrapingService(session)


Service = Annotated[ScrapingService, Depends(get_scraping_service)]


def queue_run(
    service: ScrapingService, source_id: uuid.UUID, trigger: ScrapingTrigger
) -> dict[str, object]:
    """Crée une collecte PENDING et l'envoie au worker Celery."""
    from app.modules.scraping.tasks import execute_scraping_run

    run = service.request_run(source_id, trigger)
    try:
        execute_scraping_run.delay(str(run.id))
    except Exception as exc:
        logger.error("Scraping task not queued: %s", type(exc).__name__)
        run.status = ScrapingRunStatus.FAILED
        run.error_message = "Worker unavailable"
        run.finished_at = utcnow()
        service.session.commit()
        raise ServiceUnavailableError(
            "The background worker is unavailable", code="WORKER_UNAVAILABLE"
        ) from exc
    service.session.refresh(run)
    return {"run_id": run.id, "status": run.status}


@router.post(
    "/sources/{source_id}/run",
    response_model=ApiResponse[RunRequestResult],
    status_code=status.HTTP_202_ACCEPTED,
    summary="Lancer une collecte (admin)",
    description="La collecte s'exécute en tâche de fond. Suivez-la avec GET /scraping/runs/{run_id} "
    "ou l'événement WebSocket `scraping_run`.",
    responses=error_responses(401, 403, 404, 422, 503),
)
def run_source(source_id: uuid.UUID, _admin: SuperUser, service: Service):
    return ok(queue_run(service, source_id, ScrapingTrigger.MANUAL))


@router.post(
    "/sources/{source_id}/test",
    response_model=ApiResponse[SourceTestResult],
    summary="Tester une source sans rien enregistrer (admin)",
    description="Exécute FETCH + PARSE + NORMALIZE et renvoie un aperçu des 5 premières offres. "
    "Idéal pour mettre au point la configuration d'un adapter.",
    responses=error_responses(401, 403, 404, 422),
)
def test_source(source_id: uuid.UUID, _admin: SuperUser, service: Service):
    return ok(service.test_source(source_id))


@router.get(
    "/scraping/adapters",
    response_model=ApiResponse[list[AdapterInfo]],
    summary="Adapters disponibles et schéma de leur configuration",
    responses=error_responses(401),
)
def get_adapters(_user: CurrentUser):
    return ok(
        [
            {
                "key": adapter.key,
                "description": adapter.description,
                "source_types": sorted(adapter.source_types),
                "respects_robots_txt": adapter.respects_robots_txt,
                "configuration_schema": adapter.config_model.model_json_schema(),
            }
            for adapter in list_adapters()
        ]
    )


@router.get(
    "/scraping/runs",
    response_model=ApiResponse[Page[ScrapingRunRead]],
    summary="Historique des collectes",
    responses=error_responses(401),
)
def list_runs(
    _user: CurrentUser,
    service: Service,
    pagination: PaginationParams = Depends(),
    source_id: uuid.UUID | None = None,
    status_filter: ScrapingRunStatus | None = None,
):
    items, total = service.list_runs(pagination, source_id, status_filter)
    return ok(build_page(items, total, pagination))


@router.get(
    "/scraping/runs/{run_id}",
    response_model=ApiResponse[ScrapingRunRead],
    summary="Détail d'une collecte",
    responses=error_responses(401, 404),
)
def get_run(run_id: uuid.UUID, _user: CurrentUser, service: Service):
    return ok(service.get_run(run_id))


@router.post(
    "/scraping/runs/{run_id}/cancel",
    response_model=ApiResponse[ScrapingRunRead],
    summary="Annuler une collecte en attente ou en cours (admin)",
    responses=error_responses(401, 403, 404, 422),
)
def cancel_run(run_id: uuid.UUID, _admin: SuperUser, service: Service):
    return ok(service.cancel_run(run_id))
