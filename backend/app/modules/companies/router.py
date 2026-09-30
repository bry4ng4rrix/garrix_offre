import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Query, status

from app.api.dependencies import CurrentUser, SuperUser
from app.modules.companies.dependencies import get_company_service
from app.modules.companies.schemas import CompanyCreate, CompanyRead, CompanyUpdate
from app.modules.companies.service import CompanyService
from app.shared.pagination import Page, PaginationParams, build_page
from app.shared.schemas import ApiResponse, error_responses, ok

router = APIRouter(prefix="/companies", tags=["Companies"])

Service = Annotated[CompanyService, Depends(get_company_service)]


@router.get(
    "",
    response_model=ApiResponse[Page[CompanyRead]],
    summary="Lister les entreprises",
    responses=error_responses(401),
)
def list_companies(
    _user: CurrentUser,
    service: Service,
    pagination: PaginationParams = Depends(),
    search: str | None = Query(None, max_length=100),
    city: str | None = Query(None, max_length=100),
    country: str | None = Query(None, max_length=100),
    industry: str | None = Query(None, max_length=150),
):
    items, total = service.list_companies(pagination, search, city, country, industry)
    return ok(build_page(items, total, pagination))


@router.get(
    "/{company_id}",
    response_model=ApiResponse[CompanyRead],
    summary="Détail d'une entreprise",
    description="`field_sources` indique la provenance de chaque information collectée.",
    responses=error_responses(401, 404),
)
def get_company(company_id: uuid.UUID, _user: CurrentUser, service: Service):
    return ok(service.get(company_id))


@router.post(
    "",
    response_model=ApiResponse[CompanyRead],
    status_code=status.HTTP_201_CREATED,
    summary="Créer une entreprise (admin)",
    responses=error_responses(401, 403, 409, 422),
)
def create_company(payload: CompanyCreate, _admin: SuperUser, service: Service):
    return ok(service.create(payload))


@router.put(
    "/{company_id}",
    response_model=ApiResponse[CompanyRead],
    summary="Modifier une entreprise (admin)",
    responses=error_responses(401, 403, 404, 409, 422),
)
def update_company(
    company_id: uuid.UUID, payload: CompanyUpdate, _admin: SuperUser, service: Service
):
    return ok(service.update(company_id, payload))


@router.delete(
    "/{company_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Supprimer une entreprise (admin)",
    description="Les offres liées sont conservées (elles n'ont simplement plus d'entreprise).",
    responses=error_responses(401, 403, 404),
)
def delete_company(company_id: uuid.UUID, _admin: SuperUser, service: Service) -> None:
    service.delete(company_id)
