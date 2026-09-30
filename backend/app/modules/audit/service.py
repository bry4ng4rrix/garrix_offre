import logging
import uuid
from typing import Any

from sqlalchemy.orm import Session

from app.core.logging import redact_value
from app.modules.audit.models import AuditLog
from app.modules.audit.repository import AuditLogRepository
from app.shared.enums import ActorType
from app.shared.pagination import PaginationParams

logger = logging.getLogger("app.audit")


class AuditService:
    """Enregistre les opérations critiques (RG-17).

    `record()` ajoute la trace dans la session courante SANS commit : elle est validée
    en même temps que l'opération métier (tout ou rien).

        AuditService(session).record(
            "application.status_changed",
            actor_type=ActorType.USER, actor_id=user.id,
            entity_type="application", entity_id=application.id,
            details={"from": "ready", "to": "submitted"},
        )
    """

    def __init__(self, session: Session) -> None:
        self.repository = AuditLogRepository(session)

    def record(
        self,
        action: str,
        *,
        actor_type: ActorType = ActorType.SYSTEM,
        actor_id: uuid.UUID | None = None,
        entity_type: str | None = None,
        entity_id: uuid.UUID | str | None = None,
        details: dict[str, Any] | None = None,
    ) -> AuditLog:
        safe_details = redact_value("details", details or {})
        entry = AuditLog(
            actor_type=actor_type,
            actor_id=actor_id,
            action=action,
            entity_type=entity_type,
            entity_id=str(entity_id) if entity_id else None,
            details=safe_details,
        )
        self.repository.session.add(entry)
        logger.info(
            action,
            extra={
                "actor_type": actor_type.value,
                "actor_id": str(actor_id) if actor_id else None,
                "entity_type": entity_type,
                "entity_id": str(entity_id) if entity_id else None,
            },
        )
        return entry

    def search(
        self,
        pagination: PaginationParams,
        *,
        action: str | None = None,
        entity_type: str | None = None,
        entity_id: str | None = None,
        actor_id: uuid.UUID | None = None,
    ) -> tuple[list[AuditLog], int]:
        stmt = self.repository.search_query(action, entity_type, entity_id, actor_id)
        return self.repository.paginate(stmt, pagination)
