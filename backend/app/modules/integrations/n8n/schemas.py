import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.modules.scraping.schemas import JobPayload
from app.shared.enums import (
    ApplicationStatus,
    FetchMode,
    ScrapingRunStatus,
    SourceCategory,
    SourceType,
)


class SourceReference(BaseModel):
    """Source des offres envoyées : par id, par nom, ou rien (source technique "n8n")."""

    source_id: uuid.UUID | None = None
    source_name: str | None = Field(default=None, max_length=150)


class N8nJobIn(JobPayload, SourceReference):
    """POST /webhooks/n8n/job : une offre au format JobPayload + sa source."""


class N8nJobsIn(SourceReference):
    jobs: list[JobPayload] = Field(min_length=1, max_length=500)
    notify: bool = Field(
        default=True, description="Créer les notifications (nouvelles offres, fort score)"
    )

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "source_name": "Flux RSS Python",
                    "jobs": [
                        {
                            "external_id": "abc-1",
                            "title": "Python Developer",
                            "url": "https://example.com/jobs/abc-1",
                            "company": "Exemple SAS",
                            "location": "Remote",
                        }
                    ],
                }
            ]
        }
    )


class N8nIngestionResult(BaseModel):
    received: int
    created: int
    updated: int
    duplicates: int
    invalid: int
    job_ids: list[uuid.UUID]
    created_job_ids: list[uuid.UUID]
    high_matches: list[dict[str, Any]]
    errors: list[str]
    notification_delivery: str = Field(
        description='"backend" ou "n8n" (NOTIFICATION_DELIVERY_MODE)'
    )


class ScrapingStatusIn(SourceReference):
    status: ScrapingRunStatus
    execution_id: str | None = Field(default=None, max_length=255)
    jobs_found: int = Field(default=0, ge=0)
    jobs_created: int = Field(default=0, ge=0)
    error_message: str | None = Field(default=None, max_length=5000)
    details: dict[str, Any] = Field(default_factory=dict)


class ApplicationStatusIn(BaseModel):
    application_id: uuid.UUID
    status: ApplicationStatus = Field(description="follow_up, interview, offer ou rejected")
    note: str | None = Field(default=None, max_length=2000)


class RecruiterResponseIn(BaseModel):
    application_id: uuid.UUID | None = None
    sender_email: EmailStr
    sender_name: str | None = Field(default=None, max_length=200)
    subject: str | None = Field(default=None, max_length=500)
    body: str | None = Field(default=None, max_length=100_000)
    received_at: datetime | None = None
    message_id: str | None = Field(
        default=None, max_length=255, description="Message-ID de l'email"
    )
    user_email: EmailStr | None = Field(
        default=None, description="Compte destinataire (multi-utilisateur)"
    )

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "sender_email": "rh@example.com",
                    "subject": "Votre candidature - Développeur Python",
                    "body": "Bonjour, nous souhaitons vous rencontrer pour un entretien...",
                    "received_at": "2026-09-30T08:00:00Z",
                    "message_id": "<abc123@example.com>",
                }
            ]
        }
    )


class RecruiterResponseResult(BaseModel):
    response_id: uuid.UUID
    application_id: uuid.UUID | None
    correlation_method: str | None
    response_type: str
    duplicate: bool


class N8nSource(BaseModel):
    """Source à collecter, telle que vue par le workflow de collecte."""

    id: uuid.UUID
    name: str
    type: SourceType
    category: SourceCategory
    fetch_mode: FetchMode
    adapter: str | None
    base_url: str | None
    configuration: dict[str, Any]
    rate_limit: int | None
    priority: int


class JobAlertEmailIn(BaseModel):
    """Email d'alerte d'offres reçu par l'utilisateur (LinkedIn, Indeed, APEC...), transmis par n8n."""

    sender_email: EmailStr
    subject: str | None = Field(default=None, max_length=500)
    html: str | None = Field(default=None, max_length=2_000_000)
    text: str | None = Field(default=None, max_length=500_000)
    source_name: str | None = Field(default=None, max_length=150, description="Forcer la source")
    notify: bool = True

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "sender_email": "jobalerts-noreply@linkedin.com",
                    "subject": "Nouvelles offres : Développeur Python",
                    "html": '<a href="https://www.linkedin.com/comm/jobs/view/123">Développeur Python</a>',
                }
            ]
        }
    )


class JobAlertEmailResult(N8nIngestionResult):
    source: str
    extracted: int


class MonitoringAlertIn(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    message: str = Field(min_length=1, max_length=5000)
    level: str = Field(default="warning", pattern="^(info|warning|error)$")


class RecalculateAllResult(BaseModel):
    status: str
    jobs_matched: int | None = None
