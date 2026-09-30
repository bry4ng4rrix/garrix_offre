"""Statistiques et état des services (RG-19)."""

import logging
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.database import ping_database
from app.core.redis import ping_redis
from app.modules.integrations.n8n.client import N8nClient
from app.modules.integrations.n8n.repository import N8nWebhookEventRepository
from app.modules.monitoring.repository import MonitoringRepository
from app.modules.notifications.repository import NotificationRepository
from app.modules.preferences.repository import SearchPreferenceRepository
from app.modules.scraping.schemas import ScrapingRunRead
from app.modules.users.models import User
from app.modules.users.repository import UserRepository
from app.shared.enums import ApplicationStatus
from app.shared.utils import utcnow

logger = logging.getLogger("app.monitoring")

_STARTED_AT = time.monotonic()
RESPONDED_STATUSES = {
    ApplicationStatus.INTERVIEW,
    ApplicationStatus.OFFER,
    ApplicationStatus.REJECTED,
}


def _today_start() -> datetime:
    return utcnow().replace(hour=0, minute=0, second=0, microsecond=0)


class MonitoringService:
    """Calcule les indicateurs affichés dans l'écran "Monitoring" de Flutter."""

    def __init__(self, session: Session) -> None:
        self.session = session
        self.repository = MonitoringRepository(session)

    def overview(self, user: User) -> dict[str, Any]:
        today = _today_start()
        threshold = (
            SearchPreferenceRepository(self.session).get_or_create(user.id).matching_threshold
        )
        by_status = self.repository.applications_by_status(user.id)
        return {
            "date": today.date(),
            "jobs_found_today": self.repository.jobs_seen_since(today),
            "new_jobs_today": self.repository.jobs_created_since(today),
            "jobs_analyzed_today": self.repository.matches_computed_since(user.id, today),
            "matching_jobs_today": self.repository.matching_jobs(user.id, threshold, today),
            "matching_jobs_total": self.repository.matching_jobs(user.id, threshold),
            "matching_threshold": threshold,
            "applications_total": sum(by_status.values()),
            "applications_by_status": by_status,
            "responses_total": self.repository.responses_since(user.id),
            "responses_last_7_days": self.repository.responses_since(
                user.id, today - timedelta(days=7)
            ),
            "scraping_errors_24h": self.repository.failed_runs_since(
                utcnow() - timedelta(hours=24)
            ),
            "unread_notifications": NotificationRepository(self.session).count_unread(user.id),
            "last_n8n_executions": self._n8n_events(),
            "services": {
                "api": "ok",
                "postgres": "ok" if ping_database() else "error",
                "redis": "ok" if ping_redis() else "error",
            },
        }

    def scraping(self) -> dict[str, Any]:
        since = utcnow() - timedelta(days=7)
        return {
            "runs_by_status_7d": self.repository.runs_by_status_since(since),
            "sources": self.repository.source_stats_since(since),
            "recent_runs": [
                ScrapingRunRead.model_validate(run).model_dump(mode="json")
                for run in self.repository.recent_runs()
            ],
            "last_n8n_executions": self._n8n_events(),
        }

    def applications(self, user: User) -> dict[str, Any]:
        by_status = self.repository.applications_by_status(user.id)
        submitted = self.repository.count_submitted_ever(user.id)
        responded = self.repository.count_with_response(user.id)
        delays = self.repository.response_delays_days(user.id)
        weeks_start = _today_start() - timedelta(weeks=8)
        per_week: dict[str, int] = {}
        for submitted_at in self.repository.applications_submitted_since(user.id, weeks_start):
            week = submitted_at.strftime("%G-W%V")
            per_week[week] = per_week.get(week, 0) + 1
        interviews, offers = self.repository.interviews_and_offers(user.id)
        return {
            "total": sum(by_status.values()),
            "by_status": by_status,
            "submitted_total": submitted,
            "with_response": responded,
            "response_rate": round(responded / submitted, 3) if submitted else 0.0,
            "average_response_days": round(sum(delays) / len(delays), 1) if delays else None,
            "interviews": interviews,
            "offers": offers,
            "submitted_per_week": dict(sorted(per_week.items())),
            "responses_received": self.repository.responses_since(user.id),
        }

    def system(self, websocket_connections: int = 0) -> dict[str, Any]:
        settings = get_settings()
        return {
            "version": settings.APP_VERSION,
            "environment": settings.APP_ENV,
            "uptime_seconds": int(time.monotonic() - _STARTED_AT),
            "services": {
                "api": {"status": "ok"},
                "postgres": self._timed(ping_database),
                "redis": self._timed(ping_redis),
                "worker": self._worker_status(),
                "n8n": self._timed(N8nClient().is_healthy),
            },
            "websocket_connections": websocket_connections,
            "database_size_bytes": self.repository.database_size_bytes(),
            "storage_size_bytes": _directory_size(Path(settings.STORAGE_PATH)),
            "jobs_by_status": self.repository.jobs_by_status(),
            "users": UserRepository(self.session).count(),
            "ai_provider": settings.AI_PROVIDER,
            "notification_delivery": settings.NOTIFICATION_DELIVERY_MODE,
            "telegram_configured": settings.TELEGRAM_BOT_TOKEN is not None,
            "email_configured": settings.email_enabled,
        }

    def daily_summary(self) -> dict[str, Any]:
        """Résumé global (tous utilisateurs) pour le rapport quotidien envoyé par n8n."""
        today = _today_start()
        yesterday = today - timedelta(days=1)
        return {
            "date": today.date().isoformat(),
            "jobs_found_24h": self.repository.jobs_seen_since(yesterday),
            "new_jobs_24h": self.repository.jobs_created_since(yesterday),
            "scraping_errors_24h": self.repository.failed_runs_since(yesterday),
            "runs_by_status_24h": self.repository.runs_by_status_since(yesterday),
            "services": {
                "postgres": "ok" if ping_database() else "error",
                "redis": "ok" if ping_redis() else "error",
            },
        }

    # --- Interne ---

    def _n8n_events(self) -> list[dict[str, Any]]:
        return [
            {
                "endpoint": event.endpoint,
                "workflow": event.workflow_name,
                "execution_id": event.execution_id,
                "status": event.status,
                "error_code": event.error_code,
                "summary": event.summary,
                "received_at": event.received_at,
                "duration_ms": event.duration_ms,
            }
            for event in N8nWebhookEventRepository(self.session).latest(10)
        ]

    @staticmethod
    def _timed(check: Any) -> dict[str, Any]:
        started = time.perf_counter()
        healthy = bool(check())
        return {
            "status": "ok" if healthy else "error",
            "latency_ms": round((time.perf_counter() - started) * 1000, 1),
        }

    @staticmethod
    def _worker_status() -> dict[str, Any]:
        from app.worker import celery_app

        if celery_app.conf.task_always_eager:
            return {"status": "eager", "workers": 0}
        try:
            replies = celery_app.control.ping(timeout=1.0) or []
        except Exception as exc:  # noqa: BLE001 - broker indisponible
            logger.warning("Celery ping failed: %s", type(exc).__name__)
            return {"status": "error", "workers": 0}
        return {"status": "ok" if replies else "error", "workers": len(replies)}


def _directory_size(path: Path) -> int | None:
    if not path.exists():
        return None
    return sum(file.stat().st_size for file in path.rglob("*") if file.is_file())
