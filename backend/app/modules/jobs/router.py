import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, status
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse

from app.api.dependencies import CurrentUser, DbSession, SuperUser
from app.core.exceptions import BusinessRuleError
from app.modules.jobs.dependencies import get_job_service, job_filters
from app.modules.jobs.repository import JobFilters
from app.modules.jobs.schemas import (
    CountryCount,
    JobCreate,
    JobRawRead,
    JobRead,
    JobStateUpdate,
    JobUpdate,
    MaintenanceResult,
)
from app.modules.jobs.service import JobService
from app.modules.scraping.pipeline import JobIngestionService
from app.modules.sources.service import DEFAULT_MANUAL_SOURCE, SourceService
from app.shared.enums import DataOrigin, SourceType
from app.shared.pagination import Page, PaginationParams, build_page
from app.shared.schemas import ApiResponse, error_responses, ok

router = APIRouter(prefix="/jobs", tags=["Jobs"])

Service = Annotated[JobService, Depends(get_job_service)]
Filters = Annotated[JobFilters, Depends(job_filters)]


@router.get(
    "",
    response_model=ApiResponse[Page[JobRead]],
    summary="Rechercher des offres",
    description="Filtres combinables : search, min_score, contract_type, remote, location, "
    "country (répétable), skill, company, experience_level, source, source_category "
    "(répétable), status, published_after, published_before. "
    "Tri : sort_by=published_at|created_at|score|title et sort_order=asc|desc. "
    "La description complète n'est incluse qu'avec include_description=true.",
    responses=error_responses(401, 422),
)
def list_jobs(
    user: CurrentUser,
    service: Service,
    filters: Filters,
    pagination: PaginationParams = Depends(),
    include_description: bool = False,
):
    items, total = service.list_jobs(user, filters, pagination, include_description)
    return ok(build_page(items, total, pagination))


@router.get(
    "/countries",
    response_model=ApiResponse[list[CountryCount]],
    summary="Pays des offres (pour le filtre pays)",
    description="Nombre d'offres par pays, avec les mêmes filtres que GET /jobs (le filtre "
    "`country` lui-même est ignoré). `country: null` = offres sans pays. Tri : plus fréquent d'abord.",
    responses=error_responses(401, 422),
)
def list_job_countries(user: CurrentUser, service: Service, filters: Filters):
    return ok(service.country_counts(user, filters))


@router.post(
    "",
    response_model=ApiResponse[JobRead],
    status_code=status.HTTP_201_CREATED,
    summary="Ajouter une offre manuellement",
    description="L'offre suit le même pipeline que les offres collectées (normalisation, "
    "validation, déduplication, matching). Si elle existe déjà, l'offre existante est "
    "renvoyée avec le code 200.",
    responses=error_responses(401, 422),
)
def create_job(payload: JobCreate, user: CurrentUser, session: DbSession, service: Service):
    sources = SourceService(session)
    source = (
        sources.get(payload.source_id)
        if payload.source_id
        else sources.get_or_create_default(DEFAULT_MANUAL_SOURCE, SourceType.MANUAL)
    )
    result = JobIngestionService(session).ingest(
        [payload], source, origin=DataOrigin.MANUAL, created_by_id=user.id
    )
    if not result.job_ids:
        raise BusinessRuleError("The job is invalid", code="INVALID_JOB", details=result.errors)
    job = service.get_job(user, result.job_ids[0], mark_seen=False)
    status_code = status.HTTP_201_CREATED if result.created else status.HTTP_200_OK
    return JSONResponse(status_code=status_code, content=jsonable_encoder(ok(job)))


@router.post(
    "/maintenance/expire",
    response_model=ApiResponse[MaintenanceResult],
    summary="Expirer / archiver les anciennes offres (admin)",
    description="Offres dépassant expires_at ou non revues depuis JOB_STALE_AFTER_DAYS -> EXPIRED ; "
    "expirées depuis JOB_ARCHIVE_AFTER_DAYS -> ARCHIVED. Normalement déclenché par n8n.",
    responses=error_responses(401, 403),
)
def expire_jobs(_admin: SuperUser, service: Service):
    return ok(service.expire_outdated_jobs())


@router.get(
    "/{job_id}",
    response_model=ApiResponse[JobRead],
    summary="Détail d'une offre",
    description="Marque l'offre comme vue (elle n'est plus \"nouvelle\").",
    responses=error_responses(401, 404),
)
def get_job(job_id: uuid.UUID, user: CurrentUser, service: Service):
    return ok(service.get_job(user, job_id))


@router.patch(
    "/{job_id}/state",
    response_model=ApiResponse[JobRead],
    summary="Sauvegarder / ignorer / marquer vue une offre",
    responses=error_responses(401, 404),
)
def update_job_state(
    job_id: uuid.UUID, payload: JobStateUpdate, user: CurrentUser, service: Service
):
    return ok(service.update_state(user, job_id, payload))


@router.put(
    "/{job_id}",
    response_model=ApiResponse[JobRead],
    summary="Corriger une offre (admin)",
    description="Le changement de `status` suit le cycle NEW -> ACTIVE -> EXPIRED -> ARCHIVED.",
    responses=error_responses(401, 403, 404, 422),
)
def update_job(job_id: uuid.UUID, payload: JobUpdate, admin: SuperUser, service: Service):
    job = service.update_job(job_id, payload)
    return ok(service.build_read(admin, job))


@router.delete(
    "/{job_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Supprimer une offre (admin)",
    responses=error_responses(401, 403, 404),
)
def delete_job(job_id: uuid.UUID, _admin: SuperUser, service: Service) -> None:
    service.delete_job(job_id)


@router.get(
    "/{job_id}/raw",
    response_model=ApiResponse[JobRawRead],
    summary="Données brutes et normalisées (admin, débogage des parsers)",
    responses=error_responses(401, 403, 404),
)
def get_job_raw(job_id: uuid.UUID, _admin: SuperUser, service: Service):
    return ok(service.get_raw(job_id))
