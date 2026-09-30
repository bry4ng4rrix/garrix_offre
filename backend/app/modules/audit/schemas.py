import uuid
from datetime import datetime
from typing import Any

from app.shared.enums import ActorType
from app.shared.schemas import ORMModel


class AuditLogRead(ORMModel):
    id: uuid.UUID
    actor_type: ActorType
    actor_id: uuid.UUID | None
    action: str
    entity_type: str | None
    entity_id: str | None
    details: dict[str, Any]
    created_at: datetime
