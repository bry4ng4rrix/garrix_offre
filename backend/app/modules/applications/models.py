import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import ForeignKey, Index, String, Text, UniqueConstraint, func, text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base, TimestampMixin, UUIDPrimaryKeyMixin, enum_column
from app.modules.jobs.models import Job
from app.shared.enums import (
    ActorType,
    ApplicationStatus,
    AutoApplyMode,
    SourceCategory,
    RecruiterResponseType,
    SubmissionMethod,
)

TERMINAL_STATUSES = (ApplicationStatus.REJECTED, ApplicationStatus.WITHDRAWN)


class Application(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Candidature d'un utilisateur à une offre (UML 18).

    RG-10 : au maximum UNE candidature active (non rejetée / non retirée) par offre et par
    utilisateur, garanti par un index unique partiel en base.
    """

    __tablename__ = "applications"
    __table_args__ = (
        Index(
            "uq_applications_active_per_job",
            "user_id",
            "job_id",
            unique=True,
            postgresql_where=text("status NOT IN ('rejected', 'withdrawn')"),
        ),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    job_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("jobs.id", ondelete="SET NULL"), index=True
    )
    # Copie du titre et de l'entreprise : la candidature reste lisible si l'offre est supprimée.
    job_title: Mapped[str] = mapped_column(String(500))
    company_name: Mapped[str | None] = mapped_column(String(255))
    status: Mapped[ApplicationStatus] = mapped_column(
        enum_column(ApplicationStatus), default=ApplicationStatus.NOT_APPLIED, index=True
    )
    cv_document_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("documents.id", ondelete="SET NULL")
    )
    cover_letter_document_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("documents.id", ondelete="SET NULL")
    )
    cover_letter_text: Mapped[str | None] = mapped_column(Text)
    email_subject: Mapped[str | None] = mapped_column(String(255))
    email_body: Mapped[str | None] = mapped_column(Text)
    notes: Mapped[str | None] = mapped_column(Text)
    # Créée par la candidature automatique (et non à la main).
    is_automatic: Mapped[bool] = mapped_column(default=False, server_default=text("false"))
    submitted_at: Mapped[datetime | None]
    submission_method: Mapped[SubmissionMethod | None] = mapped_column(
        enum_column(SubmissionMethod)
    )
    submission_reference: Mapped[str | None] = mapped_column(String(255))
    follow_up_at: Mapped[datetime | None]
    last_contact_at: Mapped[datetime | None]
    response_received_at: Mapped[datetime | None]

    job: Mapped[Job | None] = relationship(lazy="joined")

    @property
    def is_active(self) -> bool:
        return self.status not in TERMINAL_STATUSES


class ApplicationStatusHistory(UUIDPrimaryKeyMixin, Base):
    """Historique des changements de statut (auditabilité, RG-17)."""

    __tablename__ = "application_status_history"

    application_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("applications.id", ondelete="CASCADE"), index=True
    )
    from_status: Mapped[ApplicationStatus | None] = mapped_column(enum_column(ApplicationStatus))
    to_status: Mapped[ApplicationStatus] = mapped_column(enum_column(ApplicationStatus))
    note: Mapped[str | None] = mapped_column(Text)
    actor_type: Mapped[ActorType] = mapped_column(enum_column(ActorType))
    actor_id: Mapped[uuid.UUID | None]
    changed_at: Mapped[datetime] = mapped_column(server_default=func.now())


class RecruiterResponse(UUIDPrimaryKeyMixin, Base):
    """Réponse reçue d'un recruteur (email transmis par n8n, ou saisie manuelle).

    `message_id` (en-tête Message-ID de l'email) rend la réception idempotente (RG-18).
    """

    __tablename__ = "recruiter_responses"

    user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    application_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("applications.id", ondelete="SET NULL"), index=True
    )
    message_id: Mapped[str | None] = mapped_column(String(255), unique=True)
    sender_email: Mapped[str] = mapped_column(String(320))
    sender_name: Mapped[str | None] = mapped_column(String(200))
    subject: Mapped[str | None] = mapped_column(String(500))
    body: Mapped[str | None] = mapped_column(Text)
    received_at: Mapped[datetime]
    response_type: Mapped[RecruiterResponseType] = mapped_column(
        enum_column(RecruiterResponseType), default=RecruiterResponseType.OTHER
    )
    correlation_method: Mapped[str | None] = mapped_column(String(50))
    analysis: Mapped[dict[str, Any]] = mapped_column(default=dict)
    is_read: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())


class AutoApplySettings(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Réglages de la candidature automatique d'un utilisateur (désactivée par défaut).

    Activer le mode `send` vaut accord explicite pour que les candidatures correspondant à ces
    critères soient envoyées sans validation une par une (dérogation voulue à RG-10).
    """

    __tablename__ = "auto_apply_settings"
    __table_args__ = (UniqueConstraint("user_id"),)

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    enabled: Mapped[bool] = mapped_column(default=False)
    mode: Mapped[AutoApplyMode] = mapped_column(
        enum_column(AutoApplyMode), default=AutoApplyMode.SEND
    )
    min_score: Mapped[int] = mapped_column(default=80)
    daily_limit: Mapped[int] = mapped_column(default=10)
    # Catégories de sources visées (par défaut : offres d'emploi, pas les missions freelance).
    categories: Mapped[list[str]] = mapped_column(
        default=lambda: [SourceCategory.JOBS.value, SourceCategory.SERVICES.value]
    )
    countries: Mapped[list[str]] = mapped_column(default=list)
    remote_only: Mapped[bool] = mapped_column(default=False)
    excluded_keywords: Mapped[list[str]] = mapped_column(default=list)
    max_job_age_days: Mapped[int] = mapped_column(default=14)
    cv_document_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("documents.id", ondelete="SET NULL")
    )
    last_run_at: Mapped[datetime | None]
