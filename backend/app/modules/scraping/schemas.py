"""Schémas de la collecte.

`JobPayload` est LE format d'entrée commun :
- produit par les adapters (étape PARSE) ;
- envoyé par n8n sur POST /webhooks/n8n/job(s) ;
- utilisé pour la saisie manuelle (POST /jobs).

Il est volontairement tolérant : on peut envoyer `"location": "Paris, France"` au lieu
d'un objet, `"skills": ["Python", "Docker"]`, etc. La normalisation fait le reste.
"""

import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.shared.enums import (
    ContactSource,
    ScrapingRunStatus,
    ScrapingTrigger,
    SkillRequirement,
    SourceType,
)


class _Lenient(BaseModel):
    model_config = ConfigDict(extra="ignore", str_strip_whitespace=True)


class CompanyPayload(_Lenient):
    name: str | None = Field(default=None, max_length=255)
    website: str | None = None
    logo_url: str | None = None
    description: str | None = Field(default=None, max_length=10_000)
    industry: str | None = Field(default=None, max_length=150)
    employee_count: str | None = Field(default=None, max_length=50)
    address: str | None = Field(default=None, max_length=500)
    postal_code: str | None = Field(default=None, max_length=20)
    city: str | None = Field(default=None, max_length=100)
    country: str | None = Field(default=None, max_length=100)
    email: str | None = None
    phone: str | None = None
    linkedin_url: str | None = None
    facebook_url: str | None = None
    instagram_url: str | None = None


class RecruiterPayload(_Lenient):
    name: str | None = Field(default=None, max_length=200)
    first_name: str | None = Field(default=None, max_length=100)
    last_name: str | None = Field(default=None, max_length=100)
    job_title: str | None = Field(default=None, max_length=200)
    email: str | None = None
    phone: str | None = None
    linkedin_url: str | None = None
    website: str | None = None
    contact_source: ContactSource | None = None
    source_url: str | None = None


class LocationPayload(_Lenient):
    raw: str | None = Field(default=None, max_length=255)
    city: str | None = Field(default=None, max_length=100)
    country: str | None = Field(default=None, max_length=100)
    remote: bool | None = None
    hybrid: bool | None = None


class ContractPayload(_Lenient):
    type: str | None = Field(default=None, max_length=100)
    work_time: str | None = Field(default=None, max_length=50)


class SalaryPayload(_Lenient):
    min: float | None = Field(default=None, ge=0)
    max: float | None = Field(default=None, ge=0)
    currency: str | None = Field(default=None, max_length=10)
    period: str | None = Field(default=None, max_length=20)
    raw: str | None = Field(default=None, max_length=255)


class SkillPayload(_Lenient):
    name: str = Field(min_length=1, max_length=100)
    requirement: SkillRequirement = SkillRequirement.REQUIRED


class ApplicationPayload(_Lenient):
    url: str | None = None
    email: str | None = None


def _wrap(value: Any, key: str) -> Any:
    """Transforme une simple chaîne en objet : "Paris" -> {"raw": "Paris"}."""
    if isinstance(value, str | int | float) and not isinstance(value, bool):
        return {key: str(value)}
    return value


class JobPayload(_Lenient):
    """Offre collectée, avant normalisation (format commun adapters / n8n / saisie manuelle)."""

    external_id: str | None = Field(default=None, max_length=255)
    title: str = Field(min_length=1, max_length=500)
    description: str | None = Field(default=None, max_length=100_000)
    url: str | None = Field(default=None, max_length=2048, description="URL de l'offre")
    company: CompanyPayload | None = None
    recruiter: RecruiterPayload | None = None
    location: LocationPayload | None = None
    contract: ContractPayload | None = None
    salary: SalaryPayload | None = None
    experience_level: str | None = Field(default=None, max_length=100)
    min_years_experience: int | None = Field(default=None, ge=0, le=50)
    skills: list[SkillPayload] = Field(default_factory=list, max_length=100)
    languages: list[str] = Field(default_factory=list, max_length=10)
    application: ApplicationPayload | None = None
    published_at: datetime | None = None
    expires_at: datetime | None = None
    raw_data: dict[str, Any] | None = None

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "external_id": "123",
                    "title": "Développeur Full Stack Python / React (H/F)",
                    "description": "Nous recherchons un développeur Python / Django et React...",
                    "url": "https://example.com/job/123",
                    "company": {"name": "Tech Solutions", "website": "https://example.com"},
                    "location": "Paris, France",
                    "contract": "CDI",
                    "salary": "35k - 45k € / an",
                    "skills": ["Python", "Django", {"name": "Docker", "requirement": "preferred"}],
                    "application": {"url": "https://example.com/apply"},
                    "published_at": "2026-09-01T09:00:00Z",
                }
            ]
        }
    )

    @model_validator(mode="before")
    @classmethod
    def accept_simple_values(cls, data: Any) -> Any:
        if not isinstance(data, dict):
            return data
        data = dict(data)
        for field, key in (
            ("company", "name"),
            ("location", "raw"),
            ("contract", "type"),
            ("salary", "raw"),
        ):
            if field in data:
                data[field] = _wrap(data[field], key)
        if isinstance(data.get("application"), str):
            value = data["application"]
            data["application"] = {"email": value} if "@" in value else {"url": value}
        return data

    @field_validator("skills", mode="before")
    @classmethod
    def accept_skill_names(cls, value: Any) -> Any:
        if isinstance(value, list):
            return [{"name": item} if isinstance(item, str) else item for item in value if item]
        return value

    @field_validator("external_id", mode="before")
    @classmethod
    def external_id_as_text(cls, value: Any) -> Any:
        return str(value) if isinstance(value, int) else value


# --- Résultat normalisé (après l'étape NORMALIZE) ---


class NormalizedSkill(BaseModel):
    name: str
    requirement: SkillRequirement


class NormalizedJob(BaseModel):
    """Offre au format commun de l'application, prête à être validée puis enregistrée."""

    external_id: str | None
    title: str
    normalized_title: str
    description: str | None
    source_url: str | None
    company_name: str | None
    company: dict[str, Any]
    recruiter: dict[str, Any] | None
    location_raw: str | None
    city: str | None
    country: str | None
    is_remote: bool
    is_hybrid: bool
    contract_type: str | None
    work_time: str | None
    salary_min: int | None
    salary_max: int | None
    salary_currency: str | None
    salary_period: str | None
    salary_raw: str | None
    experience_level: str | None
    min_years_experience: int | None
    skills: list[NormalizedSkill]
    languages: list[str]
    application_url: str | None
    application_email: str | None
    published_at: datetime | None
    expires_at: datetime | None
    fingerprint: str
    quality_issues: list[str] = Field(default_factory=list)
    raw_data: dict[str, Any] = Field(default_factory=dict)


# --- Suivi des collectes ---


class ScrapingRunRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    source_id: uuid.UUID
    source_name: str | None = None
    trigger: ScrapingTrigger
    status: ScrapingRunStatus
    started_at: datetime | None
    finished_at: datetime | None
    jobs_found: int
    jobs_created: int
    jobs_updated: int
    jobs_duplicates: int
    jobs_invalid: int
    error_message: str | None
    details: dict[str, Any]
    external_execution_id: str | None
    created_at: datetime


class AdapterInfo(BaseModel):
    key: str
    description: str
    source_types: list[SourceType]
    respects_robots_txt: bool
    configuration_schema: dict[str, Any]


class IngestionResult(BaseModel):
    """Bilan d'une ingestion (collecte, webhook n8n ou saisie manuelle)."""

    received: int = 0
    created: int = 0
    updated: int = 0
    duplicates: int = 0
    invalid: int = 0
    job_ids: list[uuid.UUID] = Field(default_factory=list)
    created_job_ids: list[uuid.UUID] = Field(default_factory=list)
    high_matches: list[dict[str, Any]] = Field(default_factory=list)
    errors: list[str] = Field(default_factory=list)


class SourceTestResult(BaseModel):
    """Résultat d'un test de source (rien n'est enregistré)."""

    pages_fetched: int
    jobs_parsed: int
    preview: list[NormalizedJob]
    errors: list[str]


class RunRequestResult(BaseModel):
    run_id: uuid.UUID
    status: ScrapingRunStatus
