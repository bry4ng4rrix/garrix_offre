import uuid
from collections.abc import Callable
from datetime import datetime
from typing import Any

from sqlalchemy import ForeignKey, Index, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.config import get_settings
from app.core.database import Base, TimestampMixin, UUIDPrimaryKeyMixin


def _default(setting_name: str) -> Callable[[], int]:
    """Valeur par défaut lue dans la configuration (.env) au moment de la création."""
    return lambda: getattr(get_settings(), setting_name)


class MatchingSettings(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Poids des critères de matching, propres à chaque utilisateur.

    Initialisés depuis les variables MATCHING_*_WEIGHT du .env, puis modifiables
    via PUT /matching/settings. Les poids sont relatifs : le score est normalisé sur 100.
    """

    __tablename__ = "matching_settings"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True
    )
    skills_weight: Mapped[int] = mapped_column(default=_default("MATCHING_SKILLS_WEIGHT"))
    experience_weight: Mapped[int] = mapped_column(default=_default("MATCHING_EXPERIENCE_WEIGHT"))
    contract_weight: Mapped[int] = mapped_column(default=_default("MATCHING_CONTRACT_WEIGHT"))
    location_weight: Mapped[int] = mapped_column(default=_default("MATCHING_LOCATION_WEIGHT"))
    salary_weight: Mapped[int] = mapped_column(default=_default("MATCHING_SALARY_WEIGHT"))
    language_weight: Mapped[int] = mapped_column(default=_default("MATCHING_LANGUAGE_WEIGHT"))
    title_weight: Mapped[int] = mapped_column(default=_default("MATCHING_TITLE_WEIGHT"))
    experience_level_weight: Mapped[int] = mapped_column(
        default=_default("MATCHING_EXPERIENCE_LEVEL_WEIGHT")
    )


class JobMatch(UUIDPrimaryKeyMixin, Base):
    """Résultat du matching d'une offre pour un utilisateur (score 0-100 et raisons)."""

    __tablename__ = "job_matches"
    __table_args__ = (
        UniqueConstraint("user_id", "job_id"),
        Index("ix_job_matches_user_score", "user_id", "score"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    job_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("jobs.id", ondelete="CASCADE"), index=True)
    score: Mapped[int]
    matched_skills: Mapped[list[str]] = mapped_column(default=list)
    missing_skills: Mapped[list[str]] = mapped_column(default=list)
    experience_match: Mapped[bool | None]
    location_match: Mapped[bool | None]
    contract_match: Mapped[bool | None]
    salary_match: Mapped[bool | None]
    language_match: Mapped[bool | None]
    title_match: Mapped[bool | None]
    experience_level_match: Mapped[bool | None]
    reasons: Mapped[list[str]] = mapped_column(default=list)
    breakdown: Mapped[dict[str, Any]] = mapped_column(default=dict)
    computed_at: Mapped[datetime] = mapped_column(server_default=func.now())
