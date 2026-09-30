import uuid
from datetime import datetime

from sqlalchemy import Select, func, select

from app.modules.scraping.models import ScrapingRun
from app.shared.enums import ScrapingRunStatus
from app.shared.repository import BaseRepository


class ScrapingRunRepository(BaseRepository[ScrapingRun]):
    model = ScrapingRun

    def list_query(
        self, source_id: uuid.UUID | None = None, status: ScrapingRunStatus | None = None
    ) -> Select[tuple[ScrapingRun]]:
        stmt = select(ScrapingRun).order_by(ScrapingRun.created_at.desc())
        if source_id:
            stmt = stmt.where(ScrapingRun.source_id == source_id)
        if status:
            stmt = stmt.where(ScrapingRun.status == status)
        return stmt

    def current_status(self, run_id: uuid.UUID) -> ScrapingRunStatus | None:
        """Statut en base (sans recharger l'objet en mémoire) : détecte une annulation."""
        return self.session.scalar(select(ScrapingRun.status).where(ScrapingRun.id == run_id))

    def get_by_external_execution(self, execution_id: str) -> ScrapingRun | None:
        return self.session.scalar(
            select(ScrapingRun).where(ScrapingRun.external_execution_id == execution_id)
        )

    def count_by_status_since(self, since: datetime) -> dict[str, int]:
        stmt = (
            select(ScrapingRun.status, func.count())
            .where(ScrapingRun.created_at >= since)
            .group_by(ScrapingRun.status)
        )
        return {str(status): count for status, count in self.session.execute(stmt)}
