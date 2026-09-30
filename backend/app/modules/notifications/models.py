import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import ForeignKey, Index, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base, TimestampMixin, UUIDPrimaryKeyMixin, enum_column
from app.shared.enums import NotificationType


class Notification(UUIDPrimaryKeyMixin, Base):
    """Notification persistée (RG-12). Le WebSocket n'est qu'un canal de diffusion (RG-15)."""

    __tablename__ = "notifications"
    __table_args__ = (Index("ix_notifications_user_unread", "user_id", "is_read", "created_at"),)

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    type: Mapped[NotificationType] = mapped_column(enum_column(NotificationType))
    title: Mapped[str] = mapped_column(String(255))
    message: Mapped[str] = mapped_column(Text)
    data: Mapped[dict[str, Any]] = mapped_column(default=dict)
    is_read: Mapped[bool] = mapped_column(default=False)
    read_at: Mapped[datetime | None]
    # Canaux externes effectivement utilisés ("telegram", "email", "n8n") et dernière erreur.
    delivered_channels: Mapped[list[str]] = mapped_column(default=list)
    delivery_error: Mapped[str | None] = mapped_column(String(500))
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())


DEFAULT_EXTERNAL_TYPES = [
    NotificationType.HIGH_MATCH.value,
    NotificationType.APPLICATION_STATUS.value,
    NotificationType.RECRUITER_RESPONSE.value,
    NotificationType.SCRAPING_ERROR.value,
    NotificationType.SYSTEM.value,
    NotificationType.MONITORING.value,
]


class NotificationSettings(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Préférences de notification d'un utilisateur (canaux externes)."""

    __tablename__ = "notification_settings"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True
    )
    telegram_enabled: Mapped[bool] = mapped_column(default=True)
    telegram_chat_id: Mapped[str | None] = mapped_column(String(64))
    email_enabled: Mapped[bool] = mapped_column(default=False)
    email_to: Mapped[str | None] = mapped_column(String(320))
    # Types envoyés sur Telegram / Email (tous les types restent visibles dans l'application).
    external_types: Mapped[list[str]] = mapped_column(default=lambda: list(DEFAULT_EXTERNAL_TYPES))
