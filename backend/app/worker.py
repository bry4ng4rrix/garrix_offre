"""Application Celery (worker de tâches en arrière-plan).

Tâches exécutées ici :
- collecte d'une source (scraping) ;
- recalcul du matching ;
- envoi des notifications Telegram / Email ;
- maintenance des offres (expiration / archivage).

Lancement : celery -A app.worker worker --loglevel=INFO
La planification (toutes les X heures...) est faite par n8n, pas par Celery.
"""

from typing import Any

from celery import Celery
from celery.signals import setup_logging as celery_setup_logging

from app.core.config import get_settings
from app.core.logging import setup_logging

settings = get_settings()

celery_app = Celery(
    "garrix_offre",
    broker=settings.celery_broker_url,
    include=[
        "app.modules.notifications.tasks",
        "app.modules.scraping.tasks",
        "app.modules.matching.tasks",
        "app.modules.jobs.tasks",
    ],
)

celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    timezone="UTC",
    enable_utc=True,
    task_ignore_result=True,  # l'état des traitements est stocké en base (ex: ScrapingRun)
    task_acks_late=True,
    worker_prefetch_multiplier=1,
    broker_connection_retry_on_startup=True,
    task_always_eager=settings.CELERY_TASK_ALWAYS_EAGER,
    task_eager_propagates=settings.CELERY_TASK_ALWAYS_EAGER,
    task_time_limit=30 * 60,
    task_soft_time_limit=25 * 60,
)


@celery_setup_logging.connect
def configure_worker_logging(**_kwargs: Any) -> None:
    """Le worker utilise le même logging structuré que l'API."""
    setup_logging(get_settings())


# Charge tous les modèles SQLAlchemy (relations entre modules).
from app.modules import models  # noqa: E402, F401 - enregistre tous les modèles SQLAlchemy
