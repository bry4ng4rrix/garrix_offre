import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Query, status

from app.api.dependencies import CurrentUser, SuperUser
from app.modules.recruiters.dependencies import get_recruiter_service
from app.modules.recruiters.schemas import RecruiterCreate, RecruiterRead, RecruiterUpdate
from app.modules.recruiters.service import RecruiterService
from app.shared.pagination import Page, PaginationParams, build_page
from app.shared.schemas import ApiResponse, error_responses, ok

router = APIRouter(prefix="/recruiters", tags=["Recruiters"])

Service = Annotated[RecruiterService, Depends(get_recruiter_service)]


@router.get(
    "",
    response_model=ApiResponse[Page[RecruiterRead]],
    summary="Lister les recruteurs",
    responses=error_responses(401),
)
def list_recruiters(
    _user: CurrentUser,
    service: Service,
    pagination: PaginationParams = Depends(),
    search: str | None = Query(None, max_length=100),
    company_id: uuid.UUID | None = None,
):
    items, total = service.list_recruiters(pagination, search, company_id)
    return ok(build_page(items, total, pagination))


@router.get(
    "/{recruiter_id}",
    response_model=ApiResponse[RecruiterRead],
    summary="Détail d'un recruteur",
    responses=error_responses(401, 404),
)
def get_recruiter(recruiter_id: uuid.UUID, _user: CurrentUser, service: Service):
    return ok(service.get(recruiter_id))


@router.post(
    "",
    response_model=ApiResponse[RecruiterRead],
    status_code=status.HTTP_201_CREATED,
    summary="Créer un recruteur (admin)",
    description="Uniquement des coordonnées publiques. `contact_source` est obligatoire dès "
    "qu'un email ou un téléphone est fourni ; `source_url` l'est pour company_website et "
    "public_profile.",
    responses=error_responses(401, 403, 422),
)
def create_recruiter(payload: RecruiterCreate, _admin: SuperUser, service: Service):
    return ok(service.create(payload))


@router.put(
    "/{recruiter_id}",
    response_model=ApiResponse[RecruiterRead],
    summary="Modifier un recruteur (admin)",
    responses=error_responses(401, 403, 404, 422),
)
def update_recruiter(
    recruiter_id: uuid.UUID, payload: RecruiterUpdate, _admin: SuperUser, service: Service
):
    return ok(service.update(recruiter_id, payload))


@router.delete(
    "/{recruiter_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Supprimer un recruteur (admin)",
    responses=error_responses(401, 403, 404),
)
def delete_recruiter(recruiter_id: uuid.UUID, _admin: SuperUser, service: Service) -> None:
    service.delete(recruiter_id)
