import uuid

from sqlalchemy import Select, func, select, update

from app.modules.notifications.models import Notification, NotificationSettings
from app.shared.enums import NotificationType
from app.shared.repository import BaseRepository
from app.shared.utils import utcnow


class NotificationRepository(BaseRepository[Notification]):
    model = Notification

    def get_for_user(self, notification_id: uuid.UUID, user_id: uuid.UUID) -> Notification | None:
        return self.session.scalar(
            select(Notification).where(
                Notification.id == notification_id, Notification.user_id == user_id
            )
        )

    def list_query(
        self,
        user_id: uuid.UUID,
        is_read: bool | None = None,
        notification_type: NotificationType | None = None,
    ) -> Select[Notification]:
        stmt = (
            select(Notification)
            .where(Notification.user_id == user_id)
            .order_by(Notification.created_at.desc())
        )
        if is_read is not None:
            stmt = stmt.where(Notification.is_read.is_(is_read))
        if notification_type is not None:
            stmt = stmt.where(Notification.type == notification_type)
        return stmt

    def count_unread(self, user_id: uuid.UUID) -> int:
        stmt = select(func.count()).where(
            Notification.user_id == user_id, Notification.is_read.is_(False)
        )
        return self.session.scalar(stmt) or 0

    def mark_all_read(self, user_id: uuid.UUID) -> int:
        result = self.session.execute(
            update(Notification)
            .where(Notification.user_id == user_id, Notification.is_read.is_(False))
            .values(is_read=True, read_at=utcnow())
        )
        return int(getattr(result, "rowcount", 0) or 0)


class NotificationSettingsRepository(BaseRepository[NotificationSettings]):
    model = NotificationSettings

    def get_by_user(self, user_id: uuid.UUID) -> NotificationSettings | None:
        return self.session.scalar(
            select(NotificationSettings).where(NotificationSettings.user_id == user_id)
        )
