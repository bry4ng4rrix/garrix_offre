import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import ForeignKey, Index, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base, TimestampMixin, UUIDPrimaryKeyMixin, enum_column
from app.modules.companies.models import Company
from app.modules.recruiters.models import Recruiter
from app.modules.skills.models import Skill
from app.modules.sources.models import Source
from app.shared.enums import JobStatus, SkillRequirement


class JobSkill(Base):
    """Compétence demandée par une offre : obligatoire (required) ou appréciée (preferred)."""

    __tablename__ = "job_skills"

    job_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("jobs.id", ondelete="CASCADE"), primary_key=True
    )
    skill_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("skills.id", ondelete="CASCADE"), primary_key=True, index=True
    )
    requirement: Mapped[SkillRequirement] = mapped_column(
        enum_column(SkillRequirement), default=SkillRequirement.REQUIRED
    )

    skill: Mapped[Skill] = relationship(lazy="joined")


class JobSource(UUIDPrimaryKeyMixin, Base):
    """Une même offre peut être trouvée sur plusieurs sources : chaque apparition est gardée."""

    __tablename__ = "job_sources"
    __table_args__ = (UniqueConstraint("source_id", "external_id"),)

    job_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("jobs.id", ondelete="CASCADE"), index=True)
    source_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("sources.id", ondelete="CASCADE"))
    external_id: Mapped[str | None] = mapped_column(String(255))
    url: Mapped[str | None] = mapped_column(String(2048), index=True)
    first_seen_at: Mapped[datetime] = mapped_column(server_default=func.now())
    last_seen_at: Mapped[datetime] = mapped_column(server_default=func.now())

    source: Mapped[Source] = relationship(lazy="joined")


class Job(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Offre d'emploi normalisée.

    `raw_data` garde la donnée brute reçue (pour déboguer les parsers) et
    `normalized_data` le résultat de la normalisation.
    Cycle de vie (UML 17) : NEW (incomplète) -> ACTIVE (validée) -> EXPIRED -> ARCHIVED.
    """

    __tablename__ = "jobs"
    __table_args__ = (
        Index("ix_jobs_status_published_at", "status", "published_at"),
        Index("ix_jobs_company_title", "company_id", "normalized_title"),
    )

    external_id: Mapped[str | None] = mapped_column(String(255))
    source_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("sources.id", ondelete="SET NULL"), index=True
    )
    title: Mapped[str] = mapped_column(String(500))
    normalized_title: Mapped[str] = mapped_column(String(500))
    description: Mapped[str | None] = mapped_column(Text)
    company_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("companies.id", ondelete="SET NULL")
    )
    recruiter_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("recruiters.id", ondelete="SET NULL"), index=True
    )
    location: Mapped[str | None] = mapped_column(String(255))
    city: Mapped[str | None] = mapped_column(String(100))
    country: Mapped[str | None] = mapped_column(String(100))
    is_remote: Mapped[bool] = mapped_column(default=False)
    is_hybrid: Mapped[bool] = mapped_column(default=False)
    contract_type: Mapped[str | None] = mapped_column(String(50), index=True)
    work_time: Mapped[str | None] = mapped_column(String(20))
    salary_min: Mapped[int | None]
    salary_max: Mapped[int | None]
    salary_currency: Mapped[str | None] = mapped_column(String(3))
    salary_period: Mapped[str | None] = mapped_column(String(10))
    salary_raw: Mapped[str | None] = mapped_column(String(255))
    experience_level: Mapped[str | None] = mapped_column(String(40))
    min_years_experience: Mapped[int | None]
    languages: Mapped[list[str]] = mapped_column(default=list)
    application_url: Mapped[str | None] = mapped_column(String(2048))
    application_email: Mapped[str | None] = mapped_column(String(320))
    source_url: Mapped[str | None] = mapped_column(String(2048), index=True)
    fingerprint: Mapped[str] = mapped_column(String(64), index=True)
    status: Mapped[JobStatus] = mapped_column(enum_column(JobStatus), default=JobStatus.ACTIVE)
    quality_issues: Mapped[list[str]] = mapped_column(default=list)
    published_at: Mapped[datetime | None]
    expires_at: Mapped[datetime | None]
    scraped_at: Mapped[datetime | None]
    last_checked_at: Mapped[datetime | None]
    raw_data: Mapped[dict[str, Any]] = mapped_column(default=dict)
    normalized_data: Mapped[dict[str, Any]] = mapped_column(default=dict)
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )

    source: Mapped[Source | None] = relationship(lazy="joined")
    company: Mapped[Company | None] = relationship(lazy="joined")
    recruiter: Mapped[Recruiter | None] = relationship(lazy="joined")
    skills: Mapped[list[JobSkill]] = relationship(lazy="selectin", cascade="all, delete-orphan")
    sources: Mapped[list[JobSource]] = relationship(lazy="selectin", cascade="all, delete-orphan")

    @property
    def is_expired(self) -> bool:
        return self.status in {JobStatus.EXPIRED, JobStatus.ARCHIVED}

    @property
    def skill_names(self) -> list[str]:
        return [job_skill.skill.name for job_skill in self.skills]


class JobUserState(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """État d'une offre pour un utilisateur : vue, sauvegardée, ignorée (état IGNORED de l'UML)."""

    __tablename__ = "job_user_states"
    __table_args__ = (UniqueConstraint("user_id", "job_id"),)

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    job_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("jobs.id", ondelete="CASCADE"), index=True)
    is_saved: Mapped[bool] = mapped_column(default=False)
    is_ignored: Mapped[bool] = mapped_column(default=False)
    seen_at: Mapped[datetime | None]
