"""Tâches Celery du module jobs."""

from app.core.database import session_scope
from app.modules.jobs.service import JobService
from app.worker import celery_app


@celery_app.task(name="jobs.expire_outdated")
def expire_outdated_jobs() -> dict[str, int]:
    """Passe les offres trop anciennes en EXPIRED puis ARCHIVED."""
    with session_scope() as session:
        return JobService(session).expire_outdated_jobs()
