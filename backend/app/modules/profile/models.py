import uuid
from datetime import date
from typing import Any

from sqlalchemy import ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base, TimestampMixin, UUIDPrimaryKeyMixin, enum_column
from app.shared.enums import Availability, Mobility


class Profile(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Profil professionnel d'un utilisateur (1:1 avec User).

    Le salaire minimum, la devise et le télétravail sont stockés dans les préférences de
    recherche (search_preferences) : une seule source de vérité, utilisée par le matching.
    """

    __tablename__ = "profiles"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True
    )
    first_name: Mapped[str | None] = mapped_column(String(100))
    last_name: Mapped[str | None] = mapped_column(String(100))
    professional_title: Mapped[str | None] = mapped_column(String(200))
    email: Mapped[str | None] = mapped_column(String(320))
    phone: Mapped[str | None] = mapped_column(String(50))
    country: Mapped[str | None] = mapped_column(String(100))
    city: Mapped[str | None] = mapped_column(String(100))
    professional_address: Mapped[str | None] = mapped_column(String(500))
    bio: Mapped[str | None] = mapped_column(Text)
    availability: Mapped[Availability | None] = mapped_column(enum_column(Availability))
    available_from: Mapped[date | None]
    years_of_experience: Mapped[int | None]
    experience_level: Mapped[str | None] = mapped_column(String(40))
    mobility: Mapped[Mobility | None] = mapped_column(enum_column(Mobility))
    # Langues parlées : [{"code": "fr", "level": "native"}, {"code": "en", "level": "fluent"}]
    languages: Mapped[list[dict[str, Any]]] = mapped_column(default=list)
    linkedin_url: Mapped[str | None] = mapped_column(String(500))
    github_url: Mapped[str | None] = mapped_column(String(500))
    portfolio_url: Mapped[str | None] = mapped_column(String(500))
    photo_document_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("documents.id", ondelete="SET NULL")
    )

    @property
    def full_name(self) -> str | None:
        parts = [part for part in (self.first_name, self.last_name) if part]
        return " ".join(parts) or None

    @property
    def language_codes(self) -> list[str]:
        return [language["code"] for language in self.languages if language.get("code")]
