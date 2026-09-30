import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import ForeignKey, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base, UUIDPrimaryKeyMixin, enum_column
from app.modules.sources.models import Source
from app.shared.enums import ScrapingRunStatus, ScrapingTrigger


class ScrapingRun(UUIDPrimaryKeyMixin, Base):
    """Une exécution de collecte pour une source (UML 19).

    PENDING -> RUNNING -> SUCCESS | PARTIAL_SUCCESS | FAILED, ou CANCELLED.
    """

    __tablename__ = "scraping_runs"

    source_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("sources.id", ondelete="CASCADE"), index=True
    )
    trigger: Mapped[ScrapingTrigger] = mapped_column(enum_column(ScrapingTrigger))
    status: Mapped[ScrapingRunStatus] = mapped_column(
        enum_column(ScrapingRunStatus), default=ScrapingRunStatus.PENDING, index=True
    )
    started_at: Mapped[datetime | None]
    finished_at: Mapped[datetime | None]
    jobs_found: Mapped[int] = mapped_column(default=0)
    jobs_created: Mapped[int] = mapped_column(default=0)
    jobs_updated: Mapped[int] = mapped_column(default=0)
    jobs_duplicates: Mapped[int] = mapped_column(default=0)
    jobs_invalid: Mapped[int] = mapped_column(default=0)
    error_message: Mapped[str | None] = mapped_column(Text)
    details: Mapped[dict[str, Any]] = mapped_column(default=dict)
    # Identifiant d'exécution n8n quand la collecte a été faite par n8n (idempotence).
    external_execution_id: Mapped[str | None] = mapped_column(String(255), unique=True)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now(), index=True)

    source: Mapped[Source] = relationship(lazy="joined")

    @property
    def source_name(self) -> str | None:
        return self.source.name if self.source else None
