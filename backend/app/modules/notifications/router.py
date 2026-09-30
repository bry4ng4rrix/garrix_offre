import uuid
from typing import Annotated, Any

from fastapi import APIRouter, Depends, status

from app.api.dependencies import CurrentUser
from app.core.config import get_settings
from app.modules.notifications.dependencies import get_notification_service
from app.modules.notifications.models import NotificationSettings
from app.modules.notifications.schemas import (
    NotificationRead,
    NotificationSettingsRead,
    NotificationSettingsUpdate,
    ReadAllResult,
    UnreadCount,
)
from app.modules.notifications.service import NotificationService
from app.shared.enums import NotificationType
from app.shared.pagination import Page, PaginationParams, build_page
from app.shared.schemas import ApiResponse, error_responses, ok

router = APIRouter(prefix="/notifications", tags=["Notifications"])

Service = Annotated[NotificationService, Depends(get_notification_service)]


def _settings_payload(row: NotificationSettings) -> dict[str, Any]:
    app_settings = get_settings()
    return {
        "telegram_enabled": row.telegram_enabled,
        "telegram_chat_id": row.telegram_chat_id,
        "email_enabled": row.email_enabled,
        "email_to": row.email_to,
        "external_types": row.external_types,
        "telegram_configured": app_settings.TELEGRAM_BOT_TOKEN is not None,
        "email_configured": app_settings.email_enabled,
    }


@router.get(
    "",
    response_model=ApiResponse[Page[NotificationRead]],
    summary="Lister mes notifications",
    description="Les plus récentes d'abord. Après une reconnexion WebSocket, Flutter relit ici "
    "les notifications non lues (`is_read=false`).",
    responses=error_responses(401),
)
def list_notifications(
    user: CurrentUser,
    service: Service,
    pagination: PaginationParams = Depends(),
    is_read: bool | None = None,
    type: NotificationType | None = None,
):
    items, total = service.list_notifications(user, pagination, is_read, type)
    return ok(build_page(items, total, pagination))


@router.get(
    "/unread-count",
    response_model=ApiResponse[UnreadCount],
    summary="Nombre de notifications non lues",
    responses=error_responses(401),
)
def unread_count(user: CurrentUser, service: Service):
    return ok({"unread": service.count_unread(user)})


@router.patch(
    "/read-all",
    response_model=ApiResponse[ReadAllResult],
    summary="Tout marquer comme lu",
    responses=error_responses(401),
)
def read_all(user: CurrentUser, service: Service):
    return ok({"updated": service.mark_all_read(user)})


@router.get(
    "/settings",
    response_model=ApiResponse[NotificationSettingsRead],
    summary="Mes préférences de notification",
    responses=error_responses(401),
)
def get_settings_endpoint(user: CurrentUser, service: Service):
    return ok(_settings_payload(service.read_settings(user)))


@router.put(
    "/settings",
    response_model=ApiResponse[NotificationSettingsRead],
    summary="Modifier mes préférences de notification",
    description="Choisit les canaux externes (Telegram, Email) et les types de notifications "
    "qui y sont envoyés. Toutes les notifications restent visibles dans l'application.",
    responses=error_responses(401, 422),
)
def update_settings(payload: NotificationSettingsUpdate, user: CurrentUser, service: Service):
    return ok(_settings_payload(service.update_settings(user, payload)))


@router.patch(
    "/{notification_id}/read",
    response_model=ApiResponse[NotificationRead],
    summary="Marquer une notification comme lue",
    responses=error_responses(401, 404),
)
def mark_read(notification_id: uuid.UUID, user: CurrentUser, service: Service):
    return ok(service.mark_read(user, notification_id))


@router.delete(
    "/{notification_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Supprimer une notification",
    responses=error_responses(401, 404),
)
def delete_notification(notification_id: uuid.UUID, user: CurrentUser, service: Service) -> None:
    service.delete(user, notification_id)
