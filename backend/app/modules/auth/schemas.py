from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

from app.modules.users.schemas import validate_password_strength


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(max_length=128)

    model_config = ConfigDict(
        json_schema_extra={"examples": [{"email": "jane.doe@example.com", "password": "Passw0rd!"}]}
    )

    @field_validator("password")
    @classmethod
    def check_strength(cls, value: str) -> str:
        return validate_password_strength(value)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)

    model_config = ConfigDict(
        json_schema_extra={"examples": [{"email": "jane.doe@example.com", "password": "Passw0rd!"}]}
    )


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=20, max_length=256)


class LogoutRequest(BaseModel):
    refresh_token: str | None = Field(default=None, max_length=256)
    all_devices: bool = Field(default=False, description="Révoque toutes les sessions")


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"  # noqa: S105 - type de token OAuth, pas un secret
    expires_in: int = Field(description="Durée de validité de l'access token, en secondes")
