import uuid
from typing import Any

from pydantic import ValidationError
from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError, ConflictError, NotFoundError
from app.modules.scraping.registry import get_adapter_class
from app.modules.sources.models import Source
from app.modules.sources.repository import SourceRepository
from app.modules.sources.schemas import SourceCreate, SourceUpdate
from app.shared.enums import SourceCategory, SourceType
from app.shared.pagination import PaginationParams
from app.shared.utils import utcnow

DEFAULT_WEBHOOK_SOURCE = "n8n"
DEFAULT_MANUAL_SOURCE = "Saisie manuelle"


class SourceService:
    """Configuration des sources d'offres (lecture pour tous, écriture admin)."""

    def __init__(self, session: Session) -> None:
        self.session = session
        self.repository = SourceRepository(session)

    def list_sources(
        self,
        pagination: PaginationParams,
        enabled: bool | None = None,
        source_type: SourceType | None = None,
        category: SourceCategory | None = None,
    ) -> tuple[list[Source], int]:
        stmt = self.repository.list_query(enabled, source_type, category=category)
        return self.repository.paginate(stmt, pagination)

    def get(self, source_id: uuid.UUID) -> Source:
        source = self.repository.get(source_id)
        if source is None:
            raise NotFoundError("Source not found", code="SOURCE_NOT_FOUND")
        return source

    def create(self, data: SourceCreate) -> Source:
        if self.repository.get_by_name(data.name):
            raise ConflictError("A source with this name already exists", code="SOURCE_EXISTS")
        values = data.model_dump(mode="json")
        values["configuration"] = self._validated_configuration(
            data.type, data.adapter, data.configuration
        )
        source = self.repository.add(Source(**values))
        self.session.commit()
        return source

    def update(self, source_id: uuid.UUID, data: SourceUpdate) -> Source:
        source = self.get(source_id)
        updates = data.model_dump(mode="json", exclude_unset=True)
        new_name = updates.get("name")
        if new_name and new_name != source.name and self.repository.get_by_name(new_name):
            raise ConflictError("A source with this name already exists", code="SOURCE_EXISTS")
        for field, value in updates.items():
            setattr(source, field, value)
        source.configuration = self._validated_configuration(
            SourceType(source.type), source.adapter, source.configuration
        )
        self.session.commit()
        return source

    def delete(self, source_id: uuid.UUID) -> None:
        self.repository.delete(self.get(source_id))
        self.session.commit()

    def list_collectable(self) -> list[Source]:
        return self.repository.list_collectable()

    def get_or_create_default(self, name: str, source_type: SourceType) -> Source:
        """Source technique utilisée quand une offre arrive sans source (n8n, saisie manuelle)."""
        source = self.repository.get_by_name(name)
        if source is None:
            source = self.repository.add(
                Source(name=name, type=source_type, enabled=True, scraping_enabled=False)
            )
        return source

    def record_run_result(self, source: Source, success: bool, error: str | None = None) -> None:
        now = utcnow()
        source.last_run_at = now
        if success:
            source.last_success_at = now
            source.last_error = None
        else:
            source.last_error = (error or "Unknown error")[:2000]

    @staticmethod
    def _validated_configuration(
        source_type: SourceType, adapter: str | None, configuration: dict[str, Any]
    ) -> dict[str, Any]:
        """La configuration est vérifiée par le modèle de l'adapter choisi (erreur 422 sinon)."""
        if adapter is None:
            # Sans adapter, le backend ne collecte pas cette source (MANUAL, WEBHOOK ou fetch_mode=n8n).
            return configuration
        adapter_class = get_adapter_class(adapter)
        if adapter_class is None:
            raise BusinessRuleError(
                "Unknown adapter", code="UNKNOWN_ADAPTER", details={"adapter": adapter}
            )
        if source_type not in adapter_class.source_types:
            raise BusinessRuleError(
                f"Adapter '{adapter}' does not support source type '{source_type.value}'",
                code="ADAPTER_TYPE_MISMATCH",
            )
        try:
            return adapter_class.config_model.model_validate(configuration).model_dump(mode="json")
        except ValidationError as exc:
            details = [
                {"field": ".".join(str(part) for part in error["loc"]), "message": error["msg"]}
                for error in exc.errors()
            ]
            raise BusinessRuleError(
                "Invalid source configuration", code="INVALID_SOURCE_CONFIGURATION", details=details
            ) from exc
