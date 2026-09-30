import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Query, status

from app.api.dependencies import CurrentUser, SuperUser
from app.modules.skills.dependencies import get_skill_catalog_service, get_skill_service
from app.modules.skills.schemas import (
    CatalogSkillRead,
    CatalogSkillUpdate,
    ProfileSkillCreate,
    ProfileSkillRead,
    ProfileSkillUpdate,
    SkillCategoryCreate,
    SkillCategoryRead,
    SkillCategoryUpdate,
)
from app.modules.skills.service import SkillCatalogService, SkillService
from app.shared.pagination import Page, PaginationParams, build_page
from app.shared.schemas import ApiResponse, error_responses, ok

router = APIRouter(prefix="/skills", tags=["Skills"])

Service = Annotated[SkillService, Depends(get_skill_service)]
Catalog = Annotated[SkillCatalogService, Depends(get_skill_catalog_service)]


# --- Catalogue et catégories (déclarés avant /{id} pour éviter les conflits de routes) ---


@router.get(
    "/catalog",
    response_model=ApiResponse[Page[CatalogSkillRead]],
    summary="Rechercher dans le catalogue de compétences",
    description="Utile pour l'autocomplétion dans Flutter.",
    responses=error_responses(401),
)
def search_catalog(
    _user: CurrentUser,
    catalog: Catalog,
    pagination: PaginationParams = Depends(),
    search: str | None = Query(None, max_length=100),
    category: str | None = Query(None, max_length=50),
):
    items, total = catalog.search(pagination, search, category)
    return ok(build_page(items, total, pagination))


@router.patch(
    "/catalog/{skill_id}",
    response_model=ApiResponse[CatalogSkillRead],
    summary="Modifier une compétence du catalogue (admin)",
    description="Permet d'ajouter des alias (ex: 'reactjs' pour React) utilisés lors de "
    "l'analyse des offres.",
    responses=error_responses(401, 403, 404, 422),
)
def update_catalog_skill(
    skill_id: uuid.UUID, payload: CatalogSkillUpdate, _admin: SuperUser, catalog: Catalog
):
    return ok(catalog.update_catalog_skill(skill_id, payload))


@router.get(
    "/categories",
    response_model=ApiResponse[list[SkillCategoryRead]],
    summary="Lister les catégories de compétences",
    responses=error_responses(401),
)
def list_categories(_user: CurrentUser, catalog: Catalog):
    return ok(catalog.list_categories())


@router.post(
    "/categories",
    response_model=ApiResponse[SkillCategoryRead],
    status_code=status.HTTP_201_CREATED,
    summary="Créer une catégorie (admin)",
    responses=error_responses(401, 403, 409, 422),
)
def create_category(payload: SkillCategoryCreate, _admin: SuperUser, catalog: Catalog):
    return ok(catalog.create_category(payload))


@router.put(
    "/categories/{category_id}",
    response_model=ApiResponse[SkillCategoryRead],
    summary="Modifier une catégorie (admin)",
    responses=error_responses(401, 403, 404, 422),
)
def update_category(
    category_id: uuid.UUID, payload: SkillCategoryUpdate, _admin: SuperUser, catalog: Catalog
):
    return ok(catalog.update_category(category_id, payload))


@router.delete(
    "/categories/{category_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Supprimer une catégorie (admin)",
    responses=error_responses(401, 403, 404),
)
def delete_category(category_id: uuid.UUID, _admin: SuperUser, catalog: Catalog) -> None:
    catalog.delete_category(category_id)


# --- Compétences du profil ---


@router.get(
    "",
    response_model=ApiResponse[list[ProfileSkillRead]],
    summary="Mes compétences",
    responses=error_responses(401),
)
def list_skills(user: CurrentUser, service: Service, enabled_only: bool = False):
    return ok(service.list_skills(user, enabled_only))


@router.post(
    "",
    response_model=ApiResponse[ProfileSkillRead],
    status_code=status.HTTP_201_CREATED,
    summary="Ajouter une compétence à mon profil",
    description="La compétence est créée dans le catalogue si elle n'existe pas encore.",
    responses=error_responses(401, 409, 422),
)
def add_skill(payload: ProfileSkillCreate, user: CurrentUser, service: Service):
    return ok(service.add_skill(user, payload))


@router.get(
    "/{skill_id}",
    response_model=ApiResponse[ProfileSkillRead],
    summary="Détail d'une de mes compétences",
    responses=error_responses(401, 404),
)
def get_skill(skill_id: uuid.UUID, user: CurrentUser, service: Service):
    return ok(service.get_skill(user, skill_id))


@router.put(
    "/{skill_id}",
    response_model=ApiResponse[ProfileSkillRead],
    summary="Modifier une de mes compétences",
    responses=error_responses(401, 404, 422),
)
def update_skill(
    skill_id: uuid.UUID, payload: ProfileSkillUpdate, user: CurrentUser, service: Service
):
    return ok(service.update_skill(user, skill_id, payload))


@router.delete(
    "/{skill_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Retirer une compétence de mon profil",
    responses=error_responses(401, 404),
)
def delete_skill(skill_id: uuid.UUID, user: CurrentUser, service: Service) -> None:
    service.delete_skill(user, skill_id)
