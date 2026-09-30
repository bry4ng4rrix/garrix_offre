import logging
import uuid
from typing import Any

from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.exceptions import NotFoundError
from app.modules.notifications.models import Notification, NotificationSettings
from app.modules.notifications.repository import (
    NotificationRepository,
    NotificationSettingsRepository,
)
from app.modules.notifications.schemas import NotificationRead, NotificationSettingsUpdate
from app.modules.realtime.events import EventType, publish_event
from app.modules.users.models import User
from app.modules.users.repository import UserRepository
from app.shared.enums import NotificationType
from app.shared.pagination import PaginationParams
from app.shared.utils import utcnow

logger = logging.getLogger("app.notifications")


class NotificationService:
    """Crée les notifications, les diffuse en temps réel et planifie leur envoi externe.

    Étapes de `notify()` (UML 11) :
    1. enregistrement en base (la notification n'est jamais perdue) ;
    2. publication d'un événement temps réel (le WebSocketManager le relaie à Flutter) ;
    3. si l'utilisateur le souhaite : tâche Celery d'envoi Telegram / Email.

    Attention : `notify()` fait un commit. Appelez-la APRÈS avoir validé votre opération métier.
    """

    def __init__(self, session: Session) -> None:
        self.session = session
        self.notifications = NotificationRepository(session)
        self.settings_repository = NotificationSettingsRepository(session)

    # --- Création ---

    def notify(
        self,
        user_id: uuid.UUID,
        notification_type: NotificationType,
        title: str,
        message: str,
        data: dict[str, Any] | None = None,
        *,
        send_external: bool = True,
    ) -> Notification:
        notification = self.notifications.add(
            Notification(
                user_id=user_id,
                type=notification_type,
                title=title[:255],
                message=message,
                data=data or {},
            )
        )
        wants_external = send_external and self._wants_external_delivery(user_id, notification_type)
        self.session.commit()

        payload = NotificationRead.model_validate(notification).model_dump(mode="json")
        publish_event(EventType.NOTIFICATION, payload, user_id)
        logger.info(
            "Notification created",
            extra={"user_id": str(user_id), "type": notification_type.value},
        )
        if wants_external:
            self._schedule_external_delivery(notification.id)
        return notification

    def notify_admins(
        self,
        notification_type: NotificationType,
        title: str,
        message: str,
        data: dict[str, Any] | None = None,
    ) -> list[Notification]:
        """Notifie tous les administrateurs (erreurs de scraping, monitoring...)."""
        admins = UserRepository(self.session).list_active_superusers()
        return [self.notify(admin.id, notification_type, title, message, data) for admin in admins]

    # --- Lecture / mise à jour ---

    def list_notifications(
        self,
        user: User,
        pagination: PaginationParams,
        is_read: bool | None = None,
        notification_type: NotificationType | None = None,
    ) -> tuple[list[Notification], int]:
        stmt = self.notifications.list_query(user.id, is_read, notification_type)
        return self.notifications.paginate(stmt, pagination)

    def count_unread(self, user: User) -> int:
        return self.notifications.count_unread(user.id)

    def mark_read(self, user: User, notification_id: uuid.UUID) -> Notification:
        notification = self._get_owned(user, notification_id)
        if not notification.is_read:
            notification.is_read = True
            notification.read_at = utcnow()
            self.session.commit()
        return notification

    def mark_all_read(self, user: User) -> int:
        updated = self.notifications.mark_all_read(user.id)
        self.session.commit()
        return updated

    def delete(self, user: User, notification_id: uuid.UUID) -> None:
        self.notifications.delete(self._get_owned(user, notification_id))
        self.session.commit()

    # --- Préférences ---

    def get_settings(self, user_id: uuid.UUID) -> NotificationSettings:
        settings_row = self.settings_repository.get_by_user(user_id)
        if settings_row is None:
            settings_row = self.settings_repository.add(NotificationSettings(user_id=user_id))
        return settings_row

    def read_settings(self, user: User) -> NotificationSettings:
        """Préférences de l'utilisateur (créées avec les valeurs par défaut au premier appel)."""
        settings_row = self.get_settings(user.id)
        self.session.commit()
        return settings_row

    def update_settings(self, user: User, data: NotificationSettingsUpdate) -> NotificationSettings:
        settings_row = self.get_settings(user.id)
        for field, value in data.model_dump(exclude_unset=True).items():
            if field == "external_types" and value is not None:
                value = sorted({item.value if hasattr(item, "value") else item for item in value})
            setattr(settings_row, field, value)
        self.session.commit()
        return settings_row

    # --- Interne ---

    def _get_owned(self, user: User, notification_id: uuid.UUID) -> Notification:
        notification = self.notifications.get_for_user(notification_id, user.id)
        if notification is None:
            raise NotFoundError("Notification not found", code="NOTIFICATION_NOT_FOUND")
        return notification

    def _wants_external_delivery(
        self, user_id: uuid.UUID, notification_type: NotificationType
    ) -> bool:
        settings_row = self.get_settings(user_id)
        if notification_type.value not in settings_row.external_types:
            return False
        if get_settings().NOTIFICATION_DELIVERY_MODE == "n8n":
            return True
        return settings_row.telegram_enabled or settings_row.email_enabled

    def _schedule_external_delivery(self, notification_id: uuid.UUID) -> None:
        # Import local : la tâche Celery importe elle-même ce module.
        from app.modules.notifications.tasks import deliver_notification

        try:
            deliver_notification.delay(str(notification_id))
        except Exception as exc:  # noqa: BLE001 - broker indisponible : la notif reste en base
            logger.warning("External delivery not scheduled: %s", type(exc).__name__)
