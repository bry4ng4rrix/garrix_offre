"""Tâches Celery de la collecte."""

import uuid

from app.core.database import session_scope
from app.modules.scraping.service import ScrapingService
from app.worker import celery_app


@celery_app.task(name="scraping.execute_run")
def execute_scraping_run(run_id: str) -> str:
    """Exécute une collecte (créée au préalable avec le statut PENDING)."""
    with session_scope() as session:
        run = ScrapingService(session).execute_run(uuid.UUID(run_id))
        return run.status.value
