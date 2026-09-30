import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, EmailStr, Field, model_validator

from app.modules.ai.schemas import GenerationKind
from app.shared.enums import (
    ActorType,
    ApplicationStatus,
    AutoApplyMode,
    RecruiterResponseType,
    SourceCategory,
    SubmissionMethod,
)
from app.shared.schemas import ORMModel


class ApplicationJobInfo(ORMModel):
    id: uuid.UUID
    title: str
    application_url: str | None
    application_email: str | None
    is_expired: bool


class ApplicationRead(ORMModel):
    id: uuid.UUID
    job_id: uuid.UUID | None
    job_title: str
    company_name: str | None
    status: ApplicationStatus
    cv_document_id: uuid.UUID | None
    cover_letter_document_id: uuid.UUID | None
    cover_letter_text: str | None
    email_subject: str | None
    email_body: str | None
    notes: str | None
    submitted_at: datetime | None
    submission_method: SubmissionMethod | None
    submission_reference: str | None
    follow_up_at: datetime | None
    last_contact_at: datetime | None
    response_received_at: datetime | None
    is_automatic: bool = False
    job: ApplicationJobInfo | None
    created_at: datetime
    updated_at: datetime


class ApplicationCreate(BaseModel):
    job_id: uuid.UUID | None = Field(default=None, description="Offre concernée (recommandé)")
    job_title: str | None = Field(
        default=None, max_length=500, description="Obligatoire sans job_id"
    )
    company_name: str | None = Field(default=None, max_length=255)
    status: ApplicationStatus = Field(
        default=ApplicationStatus.NOT_APPLIED, description="not_applied ou preparing"
    )
    cv_document_id: uuid.UUID | None = None
    notes: str | None = Field(default=None, max_length=10_000)
    follow_up_at: datetime | None = None

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [{"job_id": "5f0c3c1e-8a52-4a36-9f5e-2b0f1c2d3e4f", "status": "preparing"}]
        }
    )

    @model_validator(mode="after")
    def check_title(self) -> "ApplicationCreate":
        if self.job_id is None and not self.job_title:
            raise ValueError("job_title is required when job_id is not provided")
        return self


class ApplicationUpdate(BaseModel):
    """Mise à jour partielle (le statut se change avec PATCH /status)."""

    job_title: str | None = Field(default=None, min_length=1, max_length=500)
    company_name: str | None = Field(default=None, max_length=255)
    cv_document_id: uuid.UUID | None = None
    cover_letter_document_id: uuid.UUID | None = None
    cover_letter_text: str | None = Field(default=None, max_length=20_000)
    email_subject: str | None = Field(default=None, max_length=255)
    email_body: str | None = Field(default=None, max_length=20_000)
    notes: str | None = Field(default=None, max_length=10_000)
    follow_up_at: datetime | None = None


class StatusChange(BaseModel):
    status: ApplicationStatus
    note: str | None = Field(default=None, max_length=2000)

    model_config = ConfigDict(
        json_schema_extra={"examples": [{"status": "interview", "note": "Entretien le 12/10"}]}
    )


class PrepareRequest(BaseModel):
    language: str | None = Field(
        default=None, pattern=r"^[a-z]{2,3}$", description="Langue du CV à choisir"
    )
    generate_cover_letter: bool = True
    generate_email: bool = True


class GenerateRequest(BaseModel):
    kind: GenerationKind
    response_id: uuid.UUID | None = Field(default=None, description="Pour kind=recruiter_reply")
    save: bool = Field(default=True, description="Enregistrer le texte dans la candidature")


class SubmitRequest(BaseModel):
    """Validation explicite de l'envoi (RG-10) : `confirm` doit valoir true."""

    confirm: bool = Field(description="Doit être true : confirmation explicite de l'utilisateur")
    send_email: bool = Field(default=False, description="Envoyer l'email de candidature avec le CV")
    to_email: EmailStr | None = Field(
        default=None, description="Par défaut : email de candidature de l'offre"
    )
    method: SubmissionMethod | None = Field(
        default=None, description="Si déjà envoyée ailleurs : website, other"
    )
    reference: str | None = Field(
        default=None, max_length=255, description="Référence de candidature éventuelle"
    )

    model_config = ConfigDict(
        json_schema_extra={"examples": [{"confirm": True, "send_email": True}]}
    )


class StatusHistoryRead(ORMModel):
    id: uuid.UUID
    from_status: ApplicationStatus | None
    to_status: ApplicationStatus
    note: str | None
    actor_type: ActorType
    changed_at: datetime


class RecruiterResponseRead(ORMModel):
    id: uuid.UUID
    application_id: uuid.UUID | None
    sender_email: str
    sender_name: str | None
    subject: str | None
    body: str | None
    received_at: datetime
    response_type: RecruiterResponseType
    correlation_method: str | None
    analysis: dict[str, Any]
    is_read: bool
    created_at: datetime


class RecruiterResponseCreate(BaseModel):
    """Réponse reçue (saisie manuelle dans Flutter ou envoyée par n8n)."""

    application_id: uuid.UUID | None = None
    sender_email: EmailStr
    sender_name: str | None = Field(default=None, max_length=200)
    subject: str | None = Field(default=None, max_length=500)
    body: str | None = Field(default=None, max_length=100_000)
    received_at: datetime | None = None
    message_id: str | None = Field(
        default=None, max_length=255, description="En-tête Message-ID (idempotence)"
    )


class RecruiterResponseUpdate(BaseModel):
    application_id: uuid.UUID | None = None
    is_read: bool | None = None
    response_type: RecruiterResponseType | None = None


class FollowUpDue(BaseModel):
    application_id: uuid.UUID
    user_id: uuid.UUID
    job_title: str
    company_name: str | None
    submitted_at: datetime | None
    follow_up_at: datetime | None


# --- Candidature automatique ---

DEFAULT_AUTO_CATEGORIES = [SourceCategory.JOBS, SourceCategory.SERVICES]


class AutoApplySettingsRead(ORMModel):
    enabled: bool
    mode: AutoApplyMode
    min_score: int
    daily_limit: int
    categories: list[SourceCategory]
    countries: list[str]
    remote_only: bool
    excluded_keywords: list[str]
    max_job_age_days: int
    cv_document_id: uuid.UUID | None
    last_run_at: datetime | None


class AutoApplySettingsUpdate(BaseModel):
    """Champs absents = inchangés."""

    enabled: bool | None = None
    mode: AutoApplyMode | None = Field(
        default=None,
        description="prepare : candidatures prêtes, validées une par une ; send : envoyées "
        "automatiquement par email (offres avec une adresse de candidature)",
    )
    min_score: int | None = Field(default=None, ge=50, le=100)
    daily_limit: int | None = Field(default=None, ge=1, le=50)
    categories: list[SourceCategory] | None = Field(default=None, min_length=1)
    countries: list[str] | None = Field(default=None, max_length=50)
    remote_only: bool | None = None
    excluded_keywords: list[str] | None = Field(default=None, max_length=50)
    max_job_age_days: int | None = Field(default=None, ge=1, le=90)
    cv_document_id: uuid.UUID | None = None

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {"enabled": True, "mode": "send", "min_score": 85, "daily_limit": 5,
                 "categories": ["jobs", "services"], "excluded_keywords": ["stage"]}
            ]
        }
    )  # fmt: skip

    @model_validator(mode="after")
    def clean_lists(self) -> "AutoApplySettingsUpdate":
        def clean(values: list[str] | None) -> list[str] | None:
            if values is None:
                return None
            seen: dict[str, str] = {}
            for value in values:
                text = value.strip()[:100]
                if text:
                    seen.setdefault(text.lower(), text)
            return list(seen.values())

        self.countries = clean(self.countries)
        self.excluded_keywords = clean(self.excluded_keywords)
        return self


class AutoApplyStatus(BaseModel):
    """Réglages + activité du jour."""

    settings: AutoApplySettingsRead
    email_configured: bool = Field(description="false : les candidatures sont seulement préparées")
    today_count: int = Field(description="Candidatures automatiques créées aujourd'hui (UTC)")
    today_sent: int
    remaining_today: int
    eligible_jobs: int = Field(description="Offres correspondant aux critères, pas encore traitées")


class AutoApplyItem(BaseModel):
    application_id: uuid.UUID | None
    job_id: uuid.UUID
    job_title: str
    company_name: str | None
    score: int | None
    outcome: str = Field(description="sent, prepared ou error")
    detail: str | None = None


class AutoApplyRunResult(BaseModel):
    status: str = Field(description="done, queued, disabled ou limit_reached")
    sent: int = 0
    prepared: int = 0
    errors: int = 0
    items: list[AutoApplyItem] = []
