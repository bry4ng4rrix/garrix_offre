import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, EmailStr, Field, model_validator

from app.modules.ai.schemas import GenerationKind
from app.shared.enums import (
    ActorType,
    ApplicationStatus,
    RecruiterResponseType,
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
