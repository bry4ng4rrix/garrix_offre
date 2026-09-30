from sqlalchemy import select

from app.modules.integrations.n8n.models import N8nWebhookEvent
from app.shared.repository import BaseRepository


class N8nWebhookEventRepository(BaseRepository[N8nWebhookEvent]):
    model = N8nWebhookEvent

    def get_success(self, endpoint: str, idempotency_key: str) -> N8nWebhookEvent | None:
        return self.session.scalar(
            select(N8nWebhookEvent).where(
                N8nWebhookEvent.endpoint == endpoint,
                N8nWebhookEvent.idempotency_key == idempotency_key,
                N8nWebhookEvent.status == "success",
            )
        )

    def get_by_key(self, endpoint: str, idempotency_key: str) -> N8nWebhookEvent | None:
        return self.session.scalar(
            select(N8nWebhookEvent).where(
                N8nWebhookEvent.endpoint == endpoint,
                N8nWebhookEvent.idempotency_key == idempotency_key,
            )
        )

    def latest(self, limit: int = 10) -> list[N8nWebhookEvent]:
        stmt = select(N8nWebhookEvent).order_by(N8nWebhookEvent.received_at.desc()).limit(limit)
        return list(self.session.scalars(stmt))
