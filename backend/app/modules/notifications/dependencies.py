from app.api.dependencies import DbSession
from app.modules.notifications.service import NotificationService


def get_notification_service(session: DbSession) -> NotificationService:
    return NotificationService(session)
