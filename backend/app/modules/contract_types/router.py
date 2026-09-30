import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, status

from app.api.dependencies import CurrentUser, SuperUser
from app.modules.contract_types.dependencies import get_contract_type_service
from app.modules.contract_types.schemas import (
    ContractTypeCreate,
    ContractTypeRead,
    ContractTypeUpdate,
)
from app.modules.contract_types.service import ContractTypeService
from app.shared.schemas import ApiResponse, error_responses, ok

router = APIRouter(prefix="/contract-types", tags=["Contract Types"])

Service = Annotated[ContractTypeService, Depends(get_contract_type_service)]


@router.get(
    "",
    response_model=ApiResponse[list[ContractTypeRead]],
    summary="Lister les types de contrat",
    responses=error_responses(401),
)
def list_contract_types(_user: CurrentUser, service: Service, include_inactive: bool = False):
    return ok(service.list_types(include_inactive))


@router.get(
    "/{contract_type_id}",
    response_model=ApiResponse[ContractTypeRead],
    summary="Détail d'un type de contrat",
    responses=error_responses(401, 404),
)
def get_contract_type(contract_type_id: uuid.UUID, _user: CurrentUser, service: Service):
    return ok(service.get(contract_type_id))


@router.post(
    "",
    response_model=ApiResponse[ContractTypeRead],
    status_code=status.HTTP_201_CREATED,
    summary="Créer un type de contrat (admin)",
    responses=error_responses(401, 403, 409, 422),
)
def create_contract_type(payload: ContractTypeCreate, _admin: SuperUser, service: Service):
    return ok(service.create(payload))


@router.put(
    "/{contract_type_id}",
    response_model=ApiResponse[ContractTypeRead],
    summary="Modifier un type de contrat (admin)",
    responses=error_responses(401, 403, 404, 422),
)
def update_contract_type(
    contract_type_id: uuid.UUID, payload: ContractTypeUpdate, _admin: SuperUser, service: Service
):
    return ok(service.update(contract_type_id, payload))


@router.delete(
    "/{contract_type_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Supprimer un type de contrat (admin)",
    description="Le type est aussi retiré des préférences des utilisateurs. "
    "Pour le masquer sans le supprimer, utilisez `is_active=false`.",
    responses=error_responses(401, 403, 404),
)
def delete_contract_type(contract_type_id: uuid.UUID, _admin: SuperUser, service: Service) -> None:
    service.delete(contract_type_id)
