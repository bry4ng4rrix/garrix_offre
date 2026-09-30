import re
import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

from app.shared.schemas import ORMModel

PASSWORD_MIN_LENGTH = 8


def validate_password_strength(password: str) -> str:
    """Au moins 8 caractères, une lettre et un chiffre."""
    if len(password) < PASSWORD_MIN_LENGTH:
        raise ValueError(f"Password must contain at least {PASSWORD_MIN_LENGTH} characters")
    if not re.search(r"[A-Za-z]", password) or not re.search(r"\d", password):
        raise ValueError("Password must contain at least one letter and one digit")
    return password


class UserRead(ORMModel):
    id: uuid.UUID
    email: EmailStr
    is_active: bool
    is_superuser: bool
    created_at: datetime
    last_login_at: datetime | None


class UserAdminCreate(BaseModel):
    """Création d'un compte par un administrateur (utile quand les inscriptions sont fermées)."""

    email: EmailStr
    password: str = Field(max_length=128)
    is_superuser: bool = False

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {"email": "collegue@example.com", "password": "Passw0rd!", "is_superuser": False}
            ]
        }
    )

    @field_validator("password")
    @classmethod
    def check_strength(cls, value: str) -> str:
        return validate_password_strength(value)


class UserAdminUpdate(BaseModel):
    is_active: bool | None = None
    is_superuser: bool | None = None


class PasswordChange(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(max_length=128)

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [{"current_password": "OldPassw0rd", "new_password": "NewPassw0rd!"}]
        }
    )

    @field_validator("new_password")
    @classmethod
    def check_strength(cls, value: str) -> str:
        return validate_password_strength(value)
