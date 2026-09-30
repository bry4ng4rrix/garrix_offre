import uuid
from typing import Any

from sqlalchemy import ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base, TimestampMixin, UUIDPrimaryKeyMixin, enum_column
from app.shared.enums import DataOrigin


class Company(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Entreprise qui publie des offres.

    Règle : aucune information n'est inventée. Quand une donnée vient d'une collecte,
    sa provenance est conservée dans `data_source`, `source_id`, `source_url` et, champ
    par champ, dans `field_sources` (ex: {"email": "https://exemple.com/contact"}).
    """

    __tablename__ = "companies"

    name: Mapped[str] = mapped_column(String(255))
    normalized_name: Mapped[str] = mapped_column(String(255), unique=True)
    website: Mapped[str | None] = mapped_column(String(500))
    logo_url: Mapped[str | None] = mapped_column(String(1000))
    description: Mapped[str | None] = mapped_column(Text)
    industry: Mapped[str | None] = mapped_column(String(150))
    employee_count: Mapped[str | None] = mapped_column(String(50))
    address: Mapped[str | None] = mapped_column(String(500))
    postal_code: Mapped[str | None] = mapped_column(String(20))
    city: Mapped[str | None] = mapped_column(String(100))
    country: Mapped[str | None] = mapped_column(String(100))
    email: Mapped[str | None] = mapped_column(String(320))
    phone: Mapped[str | None] = mapped_column(String(50))
    linkedin_url: Mapped[str | None] = mapped_column(String(500))
    facebook_url: Mapped[str | None] = mapped_column(String(500))
    instagram_url: Mapped[str | None] = mapped_column(String(500))
    data_source: Mapped[DataOrigin] = mapped_column(
        enum_column(DataOrigin), default=DataOrigin.MANUAL
    )
    source_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("sources.id", ondelete="SET NULL")
    )
    source_url: Mapped[str | None] = mapped_column(String(2048))
    field_sources: Mapped[dict[str, Any]] = mapped_column(default=dict)
