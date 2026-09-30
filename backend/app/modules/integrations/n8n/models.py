from datetime import datetime
from typing import Any

from sqlalchemy import String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base, UUIDPrimaryKeyMixin


class N8nWebhookEvent(UUIDPrimaryKeyMixin, Base):
    """Journal des appels reçus de n8n (monitoring, audit, idempotence).

    Si n8n envoie un en-tête `Idempotency-Key`, un second appel avec la même clé sur le même
    endpoint renvoie la réponse enregistrée sans rien refaire (RG-18).
    """

    __tablename__ = "n8n_webhook_events"
    __table_args__ = (UniqueConstraint("endpoint", "idempotency_key"),)

    endpoint: Mapped[str] = mapped_column(String(100), index=True)
    idempotency_key: Mapped[str | None] = mapped_column(String(255))
    workflow_name: Mapped[str | None] = mapped_column(String(200))
    execution_id: Mapped[str | None] = mapped_column(String(255))
    status: Mapped[str] = mapped_column(String(20))  # "success" ou "error"
    error_code: Mapped[str | None] = mapped_column(String(100))
    summary: Mapped[dict[str, Any]] = mapped_column(default=dict)
    response: Mapped[dict[str, Any] | None]
    duration_ms: Mapped[int] = mapped_column(default=0)
    received_at: Mapped[datetime] = mapped_column(server_default=func.now(), index=True)
