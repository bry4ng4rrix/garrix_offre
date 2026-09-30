"""Schémas de l'API des offres.

`JobRead` suit le format "offre normalisée" attendu par Flutter : les informations sont
regroupées par blocs (source, company, recruiter, location, contract, salary, matching...).
"""

import uuid
from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel, ConfigDict, Field

from app.modules.scraping.schemas import JobPayload, SkillPayload
from app.shared.enums import (
    ApplicationStatus,
    ContactSource,
    JobStatus,
    SkillRequirement,
    SourceCategory,
)


class JobStatusFilter(StrEnum):
    """Valeurs du filtre `status` de GET /jobs."""

    NEW = "new"  # offre incomplète, en attente de validation
    ACTIVE = "active"
    EXPIRED = "expired"
    ARCHIVED = "archived"
    UNSEEN = "unseen"  # jamais ouverte par l'utilisateur
    SAVED = "saved"
    IGNORED = "ignored"
    APPLIED = "applied"
    ALL = "all"


class JobSortField(StrEnum):
    PUBLISHED_AT = "published_at"
    CREATED_AT = "created_at"
    SCORE = "score"
    TITLE = "title"


# --- Blocs de l'offre normalisée ---


class JobSourceInfo(BaseModel):
    id: uuid.UUID | None = None
    name: str | None = None
    category: SourceCategory | None = Field(
        default=None, description="jobs, clients (freelance) ou services"
    )
    url: str | None = None
    external_id: str | None = None


class AddressInfo(BaseModel):
    street: str | None = None
    postal_code: str | None = None
    city: str | None = None
    country: str | None = None


class ContactInfo(BaseModel):
    email: str | None = None
    phone: str | None = None


class JobCompanyInfo(BaseModel):
    id: uuid.UUID | None = None
    name: str | None = None
    website: str | None = None
    logo_url: str | None = None
    address: AddressInfo = Field(default_factory=AddressInfo)
    contact: ContactInfo = Field(default_factory=ContactInfo)


class JobRecruiterInfo(BaseModel):
    id: uuid.UUID | None = None
    name: str | None = None
    job_title: str | None = None
    email: str | None = None
    phone: str | None = None
    linkedin: str | None = None
    website: str | None = None
    contact_source: ContactSource | None = None


class JobLocationInfo(BaseModel):
    raw: str | None = None
    city: str | None = None
    country: str | None = None
    remote: bool = False
    hybrid: bool = False


class JobContractInfo(BaseModel):
    type: str | None = None
    work_time: str | None = None


class JobSalaryInfo(BaseModel):
    min: int | None = None
    max: int | None = None
    currency: str | None = None
    period: str | None = None
    raw: str | None = None


class JobExperienceInfo(BaseModel):
    level: str | None = None
    min_years: int | None = None


class JobSkillInfo(BaseModel):
    name: str
    category: str | None = None
    requirement: SkillRequirement


class JobMatchingInfo(BaseModel):
    score: int
    matched_skills: list[str]
    missing_skills: list[str]
    reasons: list[str]
    computed_at: datetime


class JobApplicationInfo(BaseModel):
    url: str | None = None
    email: str | None = None


class JobStatusInfo(BaseModel):
    state: str = Field(description="new, active, expired, archived ou ignored (pour vous)")
    is_new: bool = Field(description="Jamais ouverte par vous et non expirée")
    is_expired: bool
    is_saved: bool
    is_ignored: bool
    application_status: ApplicationStatus
    application_id: uuid.UUID | None = None


class JobRead(BaseModel):
    id: uuid.UUID
    title: str
    excerpt: str | None = Field(description="Début de la description (listes)")
    description: str | None = Field(
        description="Description complète (détail ou include_description)"
    )
    source: JobSourceInfo
    other_sources: list[JobSourceInfo] = Field(description="Autres sources où l'offre a été vue")
    company: JobCompanyInfo
    recruiter: JobRecruiterInfo
    location: JobLocationInfo
    contract: JobContractInfo
    salary: JobSalaryInfo
    experience: JobExperienceInfo
    skills: list[JobSkillInfo]
    languages: list[str]
    matching: JobMatchingInfo | None
    application: JobApplicationInfo
    status: JobStatusInfo
    quality_issues: list[str]
    published_at: datetime | None
    expires_at: datetime | None
    scraped_at: datetime | None
    last_checked_at: datetime | None
    created_at: datetime


# --- Entrées ---


class JobCreate(JobPayload):
    """Saisie manuelle d'une offre (elle suit le même pipeline que les offres collectées)."""

    source_id: uuid.UUID | None = Field(
        default=None, description="Par défaut : source « Saisie manuelle »"
    )


class JobUpdate(BaseModel):
    """Correction manuelle d'une offre (admin). Les champs absents ne changent pas."""

    title: str | None = Field(default=None, min_length=1, max_length=500)
    description: str | None = Field(default=None, max_length=100_000)
    contract_type: str | None = Field(default=None, max_length=50)
    work_time: str | None = Field(default=None, max_length=20)
    city: str | None = Field(default=None, max_length=100)
    country: str | None = Field(default=None, max_length=100)
    is_remote: bool | None = None
    is_hybrid: bool | None = None
    salary_min: int | None = Field(default=None, ge=0)
    salary_max: int | None = Field(default=None, ge=0)
    salary_currency: str | None = Field(default=None, pattern=r"^[A-Z]{3}$")
    salary_period: str | None = Field(default=None, pattern=r"^(year|month|day|hour)$")
    experience_level: str | None = Field(default=None, max_length=40)
    min_years_experience: int | None = Field(default=None, ge=0, le=50)
    application_url: str | None = Field(default=None, max_length=2048)
    application_email: str | None = Field(default=None, max_length=320)
    expires_at: datetime | None = None
    status: JobStatus | None = None
    skills: list[SkillPayload] | None = Field(default=None, max_length=100)


class JobStateUpdate(BaseModel):
    is_saved: bool | None = None
    is_ignored: bool | None = None
    seen: bool | None = Field(default=None, description="true = marquer comme vue")

    model_config = ConfigDict(json_schema_extra={"examples": [{"is_saved": True}]})


class JobRawRead(BaseModel):
    id: uuid.UUID
    raw_data: dict[str, object]
    normalized_data: dict[str, object]
    quality_issues: list[str]
    sources: list[JobSourceInfo]


class MaintenanceResult(BaseModel):
    expired: int
    archived: int
