"""Tâches Celery de la candidature automatique."""

import uuid
from typing import Any

from app.core.database import session_scope
from app.modules.applications.auto_apply import AutoApplyService
from app.modules.users.repository import UserRepository
from app.worker import celery_app


@celery_app.task(name="applications.auto_apply_user")
def auto_apply_user(user_id: str) -> dict[str, Any]:
    with session_scope() as session:
        user = UserRepository(session).get(uuid.UUID(user_id))
        if user is None:
            return {"status": "unknown_user"}
        return AutoApplyService(session).run(user).as_dict()


@celery_app.task(name="applications.auto_apply_all")
def auto_apply_all() -> dict[str, int]:
    """Candidature automatique de tous les utilisateurs qui l'ont activée (déclenchée par n8n)."""
    with session_scope() as session:
        return AutoApplyService(session).run_for_all()
