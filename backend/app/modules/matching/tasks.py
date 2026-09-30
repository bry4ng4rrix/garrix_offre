"""Tâches Celery du matching."""

import uuid

from app.core.database import session_scope
from app.modules.matching.service import MatchingService
from app.modules.users.repository import UserRepository
from app.shared.enums import ActorType
from app.worker import celery_app


@celery_app.task(name="matching.recalculate_user")
def recalculate_user_matches(user_id: str, actor_type: str = ActorType.USER.value) -> int:
    with session_scope() as session:
        return MatchingService(session).recalculate_for_user(
            uuid.UUID(user_id), ActorType(actor_type)
        )


@celery_app.task(name="matching.recalculate_all")
def recalculate_all_matches() -> int:
    """Recalcule les scores de tous les utilisateurs actifs (déclenché par n8n)."""
    with session_scope() as session:
        user_ids = [user.id for user in UserRepository(session).list_active()]
    total = 0
    for user_id in user_ids:
        with session_scope() as session:
            total += MatchingService(session).recalculate_for_user(user_id, ActorType.N8N)
    return total
