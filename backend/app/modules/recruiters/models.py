import uuid

from sqlalchemy import ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base, TimestampMixin, UUIDPrimaryKeyMixin, enum_column
from app.modules.companies.models import Company
from app.shared.enums import ContactSource


class Recruiter(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Recruteur (peut publier plusieurs offres).

    Règle RG-07 : uniquement des coordonnées publiques ou autorisées, jamais inventées.
    `contact_source` + `source_url` indiquent d'où vient chaque coordonnée.
    """

    __tablename__ = "recruiters"

    name: Mapped[str | None] = mapped_column(String(200))
    first_name: Mapped[str | None] = mapped_column(String(100))
    last_name: Mapped[str | None] = mapped_column(String(100))
    job_title: Mapped[str | None] = mapped_column(String(200))
    email: Mapped[str | None] = mapped_column(String(320), index=True)
    phone: Mapped[str | None] = mapped_column(String(50))
    linkedin_url: Mapped[str | None] = mapped_column(String(500))
    website: Mapped[str | None] = mapped_column(String(500))
    company_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("companies.id", ondelete="SET NULL"), index=True
    )
    contact_source: Mapped[ContactSource | None] = mapped_column(enum_column(ContactSource))
    source_url: Mapped[str | None] = mapped_column(String(2048))
    source_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("sources.id", ondelete="SET NULL")
    )
    notes: Mapped[str | None] = mapped_column(Text)

    company: Mapped[Company | None] = relationship(lazy="joined")

    @property
    def display_name(self) -> str | None:
        if self.name:
            return self.name
        parts = [part for part in (self.first_name, self.last_name) if part]
        return " ".join(parts) or None
