from sqlalchemy import Select, select

from app.modules.sources.models import Source
from app.shared.enums import SourceCategory, SourceType
from app.shared.repository import BaseRepository


class SourceRepository(BaseRepository[Source]):
    model = Source

    def get_by_name(self, name: str) -> Source | None:
        return self.session.scalar(select(Source).where(Source.name == name))

    def list_query(
        self,
        enabled: bool | None = None,
        source_type: SourceType | None = None,
        scraping_enabled: bool | None = None,
        category: SourceCategory | None = None,
    ) -> Select[Source]:
        stmt = select(Source).order_by(Source.priority.desc(), Source.name)
        if enabled is not None:
            stmt = stmt.where(Source.enabled.is_(enabled))
        if source_type is not None:
            stmt = stmt.where(Source.type == source_type)
        if scraping_enabled is not None:
            stmt = stmt.where(Source.scraping_enabled.is_(scraping_enabled))
        if category is not None:
            stmt = stmt.where(Source.category == category)
        return stmt

    def list_collectable(self) -> list[Source]:
        """Sources actives avec collecte activée (utilisé par n8n)."""
        stmt = self.list_query(enabled=True, scraping_enabled=True)
        return list(self.session.scalars(stmt))
