import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field, HttpUrl, field_validator

from app.shared.enums import Availability, LanguageLevel, Mobility, SalaryPeriod
from app.shared.geo import normalize_country

PHONE_PATTERN = r"^\+?[0-9 ().-]{6,30}$"


class LanguageSkill(BaseModel):
    code: str = Field(min_length=2, max_length=3, description="Code ISO 639-1 : fr, en, mg...")
    level: LanguageLevel

    @field_validator("code")
    @classmethod
    def lower_code(cls, value: str) -> str:
        if not value.isalpha():
            raise ValueError("Language code must contain only letters")
        return value.lower()


class ProfileRead(BaseModel):
    id: uuid.UUID
    first_name: str | None
    last_name: str | None
    full_name: str | None
    professional_title: str | None
    email: str | None
    phone: str | None
    country: str | None
    city: str | None
    professional_address: str | None
    bio: str | None
    availability: Availability | None
    available_from: date | None
    years_of_experience: int | None
    experience_level: str | None
    mobility: Mobility | None
    languages: list[LanguageSkill]
    linkedin_url: str | None
    github_url: str | None
    portfolio_url: str | None
    # Champs partagés avec /preferences (stockés une seule fois, dans les préférences)
    minimum_salary: int | None
    currency: str
    salary_period: SalaryPeriod
    remote: bool
    photo_url: str | None
    completion_percent: int = Field(description="Pourcentage de remplissage du profil")
    updated_at: datetime


class ProfileUpdate(BaseModel):
    """Mise à jour partielle : seuls les champs envoyés sont modifiés."""

    first_name: str | None = Field(default=None, max_length=100)
    last_name: str | None = Field(default=None, max_length=100)
    professional_title: str | None = Field(default=None, max_length=200)
    email: EmailStr | None = None
    phone: str | None = Field(default=None, pattern=PHONE_PATTERN)
    country: str | None = Field(default=None, max_length=100)
    city: str | None = Field(default=None, max_length=100)
    professional_address: str | None = Field(default=None, max_length=500)
    bio: str | None = Field(default=None, max_length=5000)
    availability: Availability | None = None
    available_from: date | None = None
    years_of_experience: int | None = Field(default=None, ge=0, le=60)
    experience_level: str | None = Field(default=None, max_length=40)
    mobility: Mobility | None = None
    languages: list[LanguageSkill] | None = Field(default=None, max_length=15)
    linkedin_url: HttpUrl | None = None
    github_url: HttpUrl | None = None
    portfolio_url: HttpUrl | None = None
    minimum_salary: int | None = Field(default=None, ge=0, le=100_000_000)
    currency: str | None = Field(default=None, pattern=r"^[A-Z]{3}$")
    salary_period: SalaryPeriod | None = None
    remote: bool | None = None

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "first_name": "Jane",
                    "last_name": "Doe",
                    "professional_title": "Développeuse Full Stack Python / React",
                    "city": "Paris",
                    "country": "France",
                    "availability": "one_month",
                    "years_of_experience": 4,
                    "experience_level": "mid",
                    "languages": [
                        {"code": "fr", "level": "native"},
                        {"code": "en", "level": "fluent"},
                    ],
                    "minimum_salary": 3000,
                    "currency": "EUR",
                    "salary_period": "month",
                    "remote": True,
                }
            ]
        }
    )

    @field_validator("country")
    @classmethod
    def canonical_country(cls, value: str | None) -> str | None:
        return normalize_country(value)

    @field_validator("currency", mode="before")
    @classmethod
    def upper_currency(cls, value: object) -> object:
        return value.upper() if isinstance(value, str) else value
