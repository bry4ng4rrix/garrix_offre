import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field, HttpUrl, model_validator

from app.shared.enums import ContactSource
from app.shared.schemas import ORMModel

PHONE_PATTERN = r"^\+?[0-9 ().-]{6,30}$"

# Provenances qui doivent pointer vers une page publique vérifiable.
SOURCES_REQUIRING_URL = {ContactSource.COMPANY_WEBSITE, ContactSource.PUBLIC_PROFILE}


class RecruiterRead(ORMModel):
    id: uuid.UUID
    name: str | None = Field(validation_alias="display_name")
    first_name: str | None
    last_name: str | None
    job_title: str | None
    email: str | None
    phone: str | None
    linkedin_url: str | None
    website: str | None
    company_id: uuid.UUID | None
    contact_source: ContactSource | None
    source_url: str | None
    notes: str | None
    created_at: datetime
    updated_at: datetime


def check_contact_provenance(
    email: str | None, phone: str | None, contact_source: ContactSource | None, source_url: object
) -> None:
    """RG-07 : toute coordonnée doit avoir une provenance connue."""
    if (email or phone) and contact_source is None:
        raise ValueError("contact_source is required when an email or phone is provided")
    if contact_source in SOURCES_REQUIRING_URL and not source_url:
        raise ValueError(f"source_url is required when contact_source is {contact_source}")


class RecruiterBase(BaseModel):
    first_name: str | None = Field(default=None, max_length=100)
    last_name: str | None = Field(default=None, max_length=100)
    job_title: str | None = Field(default=None, max_length=200)
    email: EmailStr | None = None
    phone: str | None = Field(default=None, pattern=PHONE_PATTERN)
    linkedin_url: HttpUrl | None = None
    website: HttpUrl | None = None
    company_id: uuid.UUID | None = None
    contact_source: ContactSource | None = None
    source_url: HttpUrl | None = None
    notes: str | None = Field(default=None, max_length=5000)


class RecruiterCreate(RecruiterBase):
    name: str | None = Field(default=None, max_length=200)

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "name": "Alex Martin",
                    "job_title": "Talent Acquisition",
                    "email": "jobs@example.com",
                    "contact_source": "job_listing",
                    "source_url": "https://example.com/job/123",
                }
            ]
        }
    )

    @model_validator(mode="after")
    def check_recruiter(self) -> "RecruiterCreate":
        if not (self.name or self.first_name or self.last_name or self.email):
            raise ValueError("A recruiter needs at least a name or an email")
        check_contact_provenance(self.email, self.phone, self.contact_source, self.source_url)
        return self


class RecruiterUpdate(RecruiterBase):
    """Mise à jour partielle ; la règle de provenance est vérifiée sur le résultat final."""

    name: str | None = Field(default=None, max_length=200)
