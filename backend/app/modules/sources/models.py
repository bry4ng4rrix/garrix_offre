from datetime import datetime
from typing import Any

from sqlalchemy import String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base, TimestampMixin, UUIDPrimaryKeyMixin, enum_column
from app.shared.enums import FetchMode, SourceCategory, SourceType


class Source(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Source d'offres : API officielle, flux RSS, page HTML autorisée, saisie manuelle, webhook.

    - `adapter` : clé de l'adapter qui sait lire cette source (voir scraping/registry.py) ;
    - `fetch_mode` : "backend" (FastAPI lit la source) ou "n8n" (n8n lit puis envoie les offres) ;
    - `configuration` : paramètres propres à l'adapter (URL du flux, sélecteurs CSS...) ;
    - `rate_limit` : nombre maximum de requêtes par minute vers cette source ;
    - `terms_reviewed` : l'administrateur a vérifié que les conditions d'utilisation du site
      autorisent la collecte automatique (obligatoire pour les sources HTML).
    """

    __tablename__ = "sources"

    name: Mapped[str] = mapped_column(String(150), unique=True)
    type: Mapped[SourceType] = mapped_column(enum_column(SourceType))
    category: Mapped[SourceCategory] = mapped_column(
        enum_column(SourceCategory), default=SourceCategory.JOBS, server_default="jobs", index=True
    )
    adapter: Mapped[str | None] = mapped_column(String(100))
    fetch_mode: Mapped[FetchMode] = mapped_column(enum_column(FetchMode), default=FetchMode.BACKEND)
    base_url: Mapped[str | None] = mapped_column(String(2048))
    enabled: Mapped[bool] = mapped_column(default=True)
    scraping_enabled: Mapped[bool] = mapped_column(default=False)
    priority: Mapped[int] = mapped_column(default=5)
    configuration: Mapped[dict[str, Any]] = mapped_column(default=dict)
    rate_limit: Mapped[int | None]
    terms_reviewed: Mapped[bool] = mapped_column(default=False)
    last_run_at: Mapped[datetime | None]
    last_success_at: Mapped[datetime | None]
    last_error: Mapped[str | None] = mapped_column(Text)
    notes: Mapped[str | None] = mapped_column(Text)

    @property
    def is_collectable(self) -> bool:
        """Vrai si le backend peut lancer une collecte automatique sur cette source."""
        return self.enabled and self.scraping_enabled and self.adapter is not None
