import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.shared.enums import NotificationType
from app.shared.schemas import ORMModel


class NotificationRead(ORMModel):
    id: uuid.UUID
    type: NotificationType
    title: str
    message: str
    data: dict[str, Any]
    is_read: bool
    read_at: datetime | None
    delivered_channels: list[str]
    created_at: datetime


class UnreadCount(BaseModel):
    unread: int


class ReadAllResult(BaseModel):
    updated: int


class NotificationSettingsRead(ORMModel):
    telegram_enabled: bool
    telegram_chat_id: str | None
    email_enabled: bool
    email_to: str | None
    external_types: list[NotificationType]
    telegram_configured: bool = Field(description="Le bot Telegram est configuré côté serveur")
    email_configured: bool = Field(description="Le serveur SMTP est configuré côté serveur")


class NotificationSettingsUpdate(BaseModel):
    telegram_enabled: bool | None = None
    telegram_chat_id: str | None = Field(default=None, max_length=64, pattern=r"^-?\d+$|^@\w+$")
    email_enabled: bool | None = None
    email_to: EmailStr | None = None
    external_types: list[NotificationType] | None = None

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "telegram_enabled": True,
                    "email_enabled": False,
                    "external_types": ["high_match", "recruiter_response"],
                }
            ]
        }
    )
