"""Envoi d'une notification déjà enregistrée sur les canaux externes.

- NOTIFICATION_DELIVERY_MODE=backend : FastAPI appelle TelegramService / EmailService.
- NOTIFICATION_DELIVERY_MODE=n8n     : FastAPI transmet la notification au workflow n8n.

Exécuté dans une tâche Celery (voir tasks.py) pour ne pas ralentir les requêtes HTTP.
"""

import logging
import uuid

from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.exceptions import ExternalServiceError
from app.modules.integrations.email.service import EmailService
from app.modules.integrations.n8n.client import N8nClient
from app.modules.integrations.telegram.service import TelegramService
from app.modules.notifications.models import Notification, NotificationSettings
from app.modules.notifications.repository import (
    NotificationRepository,
    NotificationSettingsRepository,
)
from app.modules.users.models import User
from app.modules.users.repository import UserRepository

logger = logging.getLogger("app.notifications")


class NotificationDispatcher:
    """Distribue une notification vers Telegram, Email ou n8n selon la configuration."""

    def __init__(
        self,
        session: Session,
        telegram: TelegramService | None = None,
        email: EmailService | None = None,
        n8n: N8nClient | None = None,
    ) -> None:
        self.session = session
        self.telegram = telegram or TelegramService()
        self.email = email or EmailService()
        self.n8n = n8n or N8nClient()

    def deliver(self, notification_id: uuid.UUID) -> list[str]:
        notification = NotificationRepository(self.session).get(notification_id)
        if notification is None:
            return []
        user = UserRepository(self.session).get(notification.user_id)
        if user is None or not user.is_active:
            return []
        settings_repository = NotificationSettingsRepository(self.session)
        user_settings = settings_repository.get_by_user(user.id) or settings_repository.add(
            NotificationSettings(user_id=user.id)  # préférences par défaut
        )

        if get_settings().NOTIFICATION_DELIVERY_MODE == "n8n":
            channels, errors = self._deliver_via_n8n(notification, user, user_settings)
        else:
            channels, errors = self._deliver_directly(notification, user, user_settings)

        notification.delivered_channels = channels
        notification.delivery_error = "; ".join(errors)[:500] or None
        self.session.commit()
        logger.info(
            "Notification delivered",
            extra={
                "notification_id": str(notification.id),
                "channels": channels,
                "errors": len(errors),
            },
        )
        return channels

    def _deliver_directly(
        self, notification: Notification, user: User, user_settings: NotificationSettings
    ) -> tuple[list[str], list[str]]:
        channels: list[str] = []
        errors: list[str] = []

        chat_id = telegram_chat_id_for(user, user_settings)
        if user_settings.telegram_enabled and chat_id and self.telegram.is_configured:
            try:
                self.telegram.send_notification(
                    chat_id, notification.type, notification.title, notification.message,
                    notification.data,
                )  # fmt: skip
                channels.append("telegram")
            except ExternalServiceError as exc:
                errors.append(f"telegram: {exc.code}")

        if user_settings.email_enabled and self.email.is_configured:
            try:
                self.email.send_notification(
                    user_settings.email_to or user.email, notification.type, notification.title,
                    notification.message, notification.data,
                )  # fmt: skip
                channels.append("email")
            except ExternalServiceError as exc:
                errors.append(f"email: {exc.code}")
        return channels, errors

    def _deliver_via_n8n(
        self, notification: Notification, user: User, user_settings: NotificationSettings
    ) -> tuple[list[str], list[str]]:
        payload = {
            "notification_id": str(notification.id),
            "type": notification.type.value,
            "title": notification.title,
            "message": notification.message,
            "data": notification.data,
            "channels": {
                "telegram": user_settings.telegram_enabled,
                "telegram_chat_id": telegram_chat_id_for(user, user_settings),
                "email": user_settings.email_enabled,
                "email_to": user_settings.email_to or user.email,
            },
        }
        try:
            self.n8n.send_notification(payload)
            return ["n8n"], []
        except ExternalServiceError as exc:
            return [], [f"n8n: {exc.code}"]


def telegram_chat_id_for(user: User, user_settings: NotificationSettings) -> str | None:
    """Chat Telegram de l'utilisateur.

    Le TELEGRAM_CHAT_ID du .env appartient au propriétaire de l'instance : il n'est utilisé
    que pour les administrateurs, afin de ne jamais envoyer les notifications d'un autre
    utilisateur sur le Telegram du propriétaire.
    """
    if user_settings.telegram_chat_id:
        return user_settings.telegram_chat_id
    if user.is_superuser:
        return get_settings().TELEGRAM_CHAT_ID
    return None
