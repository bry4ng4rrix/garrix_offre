import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, EmailStr, Field, HttpUrl, field_validator

from app.shared.enums import DataOrigin
from app.shared.geo import normalize_country
from app.shared.schemas import ORMModel

PHONE_PATTERN = r"^\+?[0-9 ().-]{6,30}$"


class CompanyRead(ORMModel):
    id: uuid.UUID
    name: str
    website: str | None
    logo_url: str | None
    description: str | None
    industry: str | None
    employee_count: str | None
    address: str | None
    postal_code: str | None
    city: str | None
    country: str | None
    email: str | None
    phone: str | None
    linkedin_url: str | None
    facebook_url: str | None
    instagram_url: str | None
    data_source: DataOrigin
    source_id: uuid.UUID | None
    source_url: str | None
    field_sources: dict[str, Any]
    created_at: datetime
    updated_at: datetime


class CompanyBase(BaseModel):
    website: HttpUrl | None = None
    logo_url: HttpUrl | None = None
    description: str | None = Field(default=None, max_length=10_000)
    industry: str | None = Field(default=None, max_length=150)
    employee_count: str | None = Field(default=None, max_length=50, description='Ex: "50-200"')
    address: str | None = Field(default=None, max_length=500)
    postal_code: str | None = Field(default=None, max_length=20)
    city: str | None = Field(default=None, max_length=100)
    country: str | None = Field(default=None, max_length=100)
    email: EmailStr | None = None
    phone: str | None = Field(default=None, pattern=PHONE_PATTERN)
    linkedin_url: HttpUrl | None = None
    facebook_url: HttpUrl | None = None
    instagram_url: HttpUrl | None = None
    source_url: HttpUrl | None = Field(
        default=None, description="Page publique d'où viennent les infos"
    )

    @field_validator("country")
    @classmethod
    def canonical_country(cls, value: str | None) -> str | None:
        return normalize_country(value)


class CompanyCreate(CompanyBase):
    name: str = Field(min_length=1, max_length=255)

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "name": "Tech Solutions",
                    "website": "https://example.com",
                    "industry": "Logiciel",
                    "city": "Paris",
                    "country": "France",
                }
            ]
        }
    )


class CompanyUpdate(CompanyBase):
    name: str | None = Field(default=None, min_length=1, max_length=255)
