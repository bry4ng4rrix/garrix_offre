"""Tâches Celery du module notifications."""

import uuid

from app.core.database import session_scope
from app.modules.notifications.dispatcher import NotificationDispatcher
from app.worker import celery_app


@celery_app.task(name="notifications.deliver")
def deliver_notification(notification_id: str) -> list[str]:
    """Envoie une notification sur Telegram / Email / n8n."""
    with session_scope() as session:
        return NotificationDispatcher(session).deliver(uuid.UUID(notification_id))
