"""Publication des événements temps réel.

Les services (notifications, candidatures, scraping...) appellent `publish_event()`.
L'événement part dans un canal Redis ; le `WebSocketManager` de l'API l'écoute et le
transmet aux clients Flutter connectés.

Grâce à Redis, un événement émis par un worker Celery arrive aussi aux WebSockets
ouverts sur l'API. Les services ne connaissent donc jamais le WebSocket directement.

Format d'un message reçu par Flutter :

    {"type": "notification", "data": {...}, "timestamp": "2026-01-01T10:00:00+00:00"}
"""

import json
import logging
import uuid
from enum import StrEnum
from typing import Any

from redis.exceptions import RedisError

from app.core.redis import get_redis
from app.shared.utils import utcnow

logger = logging.getLogger("app.realtime")

EVENTS_CHANNEL = "garrix:events"


class EventType(StrEnum):
    NOTIFICATION = "notification"
    NEW_JOB = "new_job"
    HIGH_MATCH = "high_match"
    APPLICATION_STATUS = "application_status"
    RECRUITER_RESPONSE = "recruiter_response"
    SCRAPING_RUN = "scraping_run"
    SCRAPING_ERROR = "scraping_error"
    MATCHING_RECALCULATED = "matching_recalculated"
    MONITORING = "monitoring"


def publish_event(
    event_type: EventType,
    data: dict[str, Any],
    user_id: uuid.UUID | None = None,
) -> None:
    """Publie un événement. `user_id=None` = diffusé à tous les utilisateurs connectés.

    Ne lève jamais d'exception : le temps réel est un bonus, la donnée est déjà en base (RG-15).
    """
    message = {
        "type": event_type.value,
        "user_id": str(user_id) if user_id else None,
        "data": data,
        "timestamp": utcnow().isoformat(),
    }
    try:
        get_redis().publish(EVENTS_CHANNEL, json.dumps(message, default=str))
    except RedisError as exc:
        logger.warning("Realtime event not published: %s", exc, extra={"event": event_type.value})
