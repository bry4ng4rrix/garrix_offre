import uuid
from typing import Annotated

from fastapi import APIRouter, Depends

from app.api.dependencies import CurrentUser, SuperUser
from app.modules.users.dependencies import get_user_service
from app.modules.users.schemas import PasswordChange, UserAdminUpdate, UserRead
from app.modules.users.service import UserService
from app.shared.pagination import Page, PaginationParams, build_page
from app.shared.schemas import ApiResponse, MessageData, error_responses, message, ok

router = APIRouter(prefix="/users", tags=["Users"])

Service = Annotated[UserService, Depends(get_user_service)]


@router.put(
    "/me/password",
    response_model=ApiResponse[MessageData],
    summary="Changer son mot de passe",
    responses=error_responses(401, 422),
)
def change_password(payload: PasswordChange, user: CurrentUser, service: Service):
    service.change_password(user, payload.current_password, payload.new_password)
    return message("Password updated")


@router.get(
    "",
    response_model=ApiResponse[Page[UserRead]],
    summary="Lister les utilisateurs (admin)",
    responses=error_responses(401, 403),
)
def list_users(_admin: SuperUser, service: Service, pagination: PaginationParams = Depends()):
    items, total = service.list_users(pagination)
    return ok(build_page(items, total, pagination))


@router.patch(
    "/{user_id}",
    response_model=ApiResponse[UserRead],
    summary="Activer / désactiver un utilisateur (admin)",
    responses=error_responses(401, 403, 404, 422),
)
def update_user(user_id: uuid.UUID, payload: UserAdminUpdate, admin: SuperUser, service: Service):
    return ok(service.admin_update(user_id, payload, admin))
