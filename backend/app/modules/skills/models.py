import uuid

from sqlalchemy import ForeignKey, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base, TimestampMixin, UUIDPrimaryKeyMixin, enum_column
from app.shared.enums import Priority, SkillLevel


class SkillCategory(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Catégorie de compétence : frontend, backend, devops..."""

    __tablename__ = "skill_categories"

    code: Mapped[str] = mapped_column(String(50), unique=True)
    name: Mapped[str] = mapped_column(String(100))
    description: Mapped[str | None] = mapped_column(Text)


class Skill(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Compétence du catalogue global (partagé entre profils et offres).

    `aliases` permet de reconnaître "ReactJS" ou "React.js" comme "React" dans une offre.
    """

    __tablename__ = "skills"

    name: Mapped[str] = mapped_column(String(100))
    normalized_name: Mapped[str] = mapped_column(String(100), unique=True)
    category_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("skill_categories.id", ondelete="SET NULL")
    )
    aliases: Mapped[list[str]] = mapped_column(default=list)

    category: Mapped[SkillCategory | None] = relationship(lazy="joined")

    @property
    def category_code(self) -> str | None:
        return self.category.code if self.category else None


class ProfileSkill(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Compétence possédée par un profil (ERD : profile_skills)."""

    __tablename__ = "profile_skills"
    __table_args__ = (UniqueConstraint("profile_id", "skill_id"),)

    profile_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("profiles.id", ondelete="CASCADE"), index=True
    )
    skill_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("skills.id", ondelete="CASCADE"))
    level: Mapped[SkillLevel] = mapped_column(
        enum_column(SkillLevel), default=SkillLevel.INTERMEDIATE
    )
    years_experience: Mapped[float | None]
    priority: Mapped[Priority] = mapped_column(enum_column(Priority), default=Priority.MEDIUM)
    enabled: Mapped[bool] = mapped_column(default=True)

    skill: Mapped[Skill] = relationship(lazy="joined")

    @property
    def name(self) -> str:
        return self.skill.name

    @property
    def category_code(self) -> str | None:
        return self.skill.category_code
