import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, status

from app.api.dependencies import CurrentUser, SuperUser
from app.modules.sources.dependencies import get_source_service
from app.modules.sources.schemas import SourceCreate, SourceRead, SourceUpdate
from app.modules.sources.service import SourceService
from app.shared.enums import SourceCategory, SourceType
from app.shared.pagination import Page, PaginationParams, build_page
from app.shared.schemas import ApiResponse, error_responses, ok

router = APIRouter(prefix="/sources", tags=["Sources"])

Service = Annotated[SourceService, Depends(get_source_service)]


@router.get(
    "",
    response_model=ApiResponse[Page[SourceRead]],
    summary="Lister les sources d'offres",
    description="Filtre `category` : jobs (offres d'emploi), clients (missions freelance), "
    "services (API de données d'offres).",
    responses=error_responses(401),
)
def list_sources(
    _user: CurrentUser,
    service: Service,
    pagination: PaginationParams = Depends(),
    enabled: bool | None = None,
    type: SourceType | None = None,
    category: SourceCategory | None = None,
):
    items, total = service.list_sources(pagination, enabled, type, category)
    return ok(build_page(items, total, pagination))


@router.get(
    "/{source_id}",
    response_model=ApiResponse[SourceRead],
    summary="Détail d'une source",
    responses=error_responses(401, 404),
)
def get_source(source_id: uuid.UUID, _user: CurrentUser, service: Service):
    return ok(service.get(source_id))


@router.post(
    "",
    response_model=ApiResponse[SourceRead],
    status_code=status.HTTP_201_CREATED,
    summary="Créer une source (admin)",
    description="La `configuration` est validée par l'adapter choisi (voir GET /scraping/adapters). "
    "Uniquement des sources autorisées : API officielles, flux RSS publics, pages HTML dont les "
    "conditions d'utilisation permettent la collecte (`terms_reviewed=true`).",
    responses=error_responses(401, 403, 409, 422),
)
def create_source(payload: SourceCreate, _admin: SuperUser, service: Service):
    return ok(service.create(payload))


@router.put(
    "/{source_id}",
    response_model=ApiResponse[SourceRead],
    summary="Modifier une source (admin)",
    responses=error_responses(401, 403, 404, 409, 422),
)
def update_source(source_id: uuid.UUID, payload: SourceUpdate, _admin: SuperUser, service: Service):
    return ok(service.update(source_id, payload))


@router.delete(
    "/{source_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Supprimer une source (admin)",
    responses=error_responses(401, 403, 404),
)
def delete_source(source_id: uuid.UUID, _admin: SuperUser, service: Service) -> None:
    service.delete(source_id)
