import uuid

from sqlalchemy import Select, select

from app.modules.audit.models import AuditLog
from app.shared.repository import BaseRepository


class AuditLogRepository(BaseRepository[AuditLog]):
    model = AuditLog

    def search_query(
        self,
        action: str | None = None,
        entity_type: str | None = None,
        entity_id: str | None = None,
        actor_id: uuid.UUID | None = None,
    ) -> Select[tuple[AuditLog]]:
        stmt = select(AuditLog).order_by(AuditLog.created_at.desc())
        if action:
            stmt = stmt.where(AuditLog.action.startswith(action))
        if entity_type:
            stmt = stmt.where(AuditLog.entity_type == entity_type)
        if entity_id:
            stmt = stmt.where(AuditLog.entity_id == entity_id)
        if actor_id:
            stmt = stmt.where(AuditLog.actor_id == actor_id)
        return stmt
