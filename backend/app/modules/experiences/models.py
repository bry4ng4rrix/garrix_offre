import uuid
from datetime import date

from sqlalchemy import ForeignKey, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base, TimestampMixin, UUIDPrimaryKeyMixin, enum_column
from app.modules.skills.models import Skill
from app.shared.enums import Priority, SkillLevel


class ExperienceLevel(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Niveau d'expérience (stage, junior, confirmé, senior, lead).

    `rank` ordonne les niveaux : le matching compare le rang du profil à celui de l'offre.
    """

    __tablename__ = "experience_levels"

    code: Mapped[str] = mapped_column(String(40), unique=True)
    name: Mapped[str] = mapped_column(String(100))
    rank: Mapped[int]
    min_years: Mapped[int] = mapped_column(default=0)
    aliases: Mapped[list[str]] = mapped_column(default=list)
    description: Mapped[str | None] = mapped_column(Text)


class Experience(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Expérience professionnelle passée ou actuelle (parcours du profil)."""

    __tablename__ = "experiences"

    profile_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("profiles.id", ondelete="CASCADE"), index=True
    )
    company_name: Mapped[str] = mapped_column(String(200))
    job_title: Mapped[str] = mapped_column(String(200))
    location: Mapped[str | None] = mapped_column(String(200))
    start_date: Mapped[date]
    end_date: Mapped[date | None]
    is_current: Mapped[bool] = mapped_column(default=False)
    description: Mapped[str | None] = mapped_column(Text)
    technologies: Mapped[list[str]] = mapped_column(default=list)

    @property
    def duration_years(self) -> float:
        end = date.today() if self.is_current or self.end_date is None else self.end_date
        return round(max((end - self.start_date).days, 0) / 365.25, 1)


class ExperiencePreference(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Technologie / expérience recherchée dans les offres (ex: React, obligatoire, priorité haute).

    - `level` et `min_years` : votre niveau et vos années sur cette technologie ;
    - `priority` : importance dans le score de matching ;
    - `is_required` : si l'offre ne mentionne pas cette technologie, le score est plafonné.
    """

    __tablename__ = "experience_preferences"
    __table_args__ = (UniqueConstraint("user_id", "skill_id"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    skill_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("skills.id", ondelete="CASCADE"))
    level: Mapped[SkillLevel] = mapped_column(
        enum_column(SkillLevel), default=SkillLevel.INTERMEDIATE
    )
    priority: Mapped[Priority] = mapped_column(enum_column(Priority), default=Priority.MEDIUM)
    min_years: Mapped[int] = mapped_column(default=0)
    is_required: Mapped[bool] = mapped_column(default=False)
    enabled: Mapped[bool] = mapped_column(default=True)

    skill: Mapped[Skill] = relationship(lazy="joined")

    @property
    def technology(self) -> str:
        return self.skill.name

    @property
    def category_code(self) -> str | None:
        return self.skill.category_code
