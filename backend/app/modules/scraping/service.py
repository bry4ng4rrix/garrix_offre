"""Orchestration d'une collecte complète pour une source.

    SOURCE -> FETCH -> PARSE -> [pipeline : NORMALIZE -> VALIDATE -> DEDUPLICATE -> SAVE
                                 -> MATCH -> NOTIFY]

L'état de chaque collecte est suivi dans ScrapingRun (UML 19) :
PENDING -> RUNNING -> SUCCESS / PARTIAL_SUCCESS / FAILED (ou CANCELLED).
Une source en échec n'empêche jamais les autres de fonctionner (RG-19).
"""

import logging
import uuid
from datetime import timedelta
from typing import Any

import httpx
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.exceptions import AppException, BusinessRuleError, NotFoundError
from app.modules.audit.service import AuditService
from app.modules.notifications.service import NotificationService
from app.modules.realtime.events import EventType, publish_event
from app.modules.scraping.http import ScrapingError
from app.modules.scraping.models import ScrapingRun
from app.modules.scraping.normalizer import NormalizerService
from app.modules.scraping.parser import ParserService
from app.modules.scraping.pipeline import JobIngestionService
from app.modules.scraping.repository import ScrapingRunRepository
from app.modules.scraping.scraper import ScraperService
from app.modules.sources.models import Source
from app.modules.sources.service import SourceService
from app.shared.enums import (
    ActorType,
    DataOrigin,
    NotificationType,
    ScrapingRunStatus,
    ScrapingTrigger,
)
from app.shared.pagination import PaginationParams
from app.shared.utils import utcnow

logger = logging.getLogger("app.scraping")

FINAL_STATUSES = {
    ScrapingRunStatus.SUCCESS,
    ScrapingRunStatus.PARTIAL_SUCCESS,
    ScrapingRunStatus.FAILED,
    ScrapingRunStatus.CANCELLED,
}
PREVIEW_SIZE = 5
STALE_RUN_AFTER = timedelta(hours=2)


class ScrapingService:
    """Lance, suit et teste les collectes des sources."""

    def __init__(self, session: Session, transport: httpx.BaseTransport | None = None) -> None:
        self.session = session
        self.runs = ScrapingRunRepository(session)
        self.sources = SourceService(session)
        self.scraper = ScraperService(transport)
        self.parser = ParserService()

    # --- Création / lecture des collectes ---

    def request_run(self, source_id: uuid.UUID, trigger: ScrapingTrigger) -> ScrapingRun:
        """Crée une collecte PENDING (vérifie d'abord que la source est collectable)."""
        source = self.sources.get(source_id)
        if not source.enabled:
            raise BusinessRuleError("This source is disabled", code="SOURCE_DISABLED")
        self.scraper.build_adapter(source).http.close()  # valide adapter / conditions d'utilisation
        run = self.runs.add(ScrapingRun(source_id=source.id, trigger=trigger))
        self.session.commit()
        return run

    def list_runs(
        self,
        pagination: PaginationParams,
        source_id: uuid.UUID | None = None,
        status: ScrapingRunStatus | None = None,
    ) -> tuple[list[ScrapingRun], int]:
        return self.runs.paginate(self.runs.list_query(source_id, status), pagination)

    def get_run(self, run_id: uuid.UUID) -> ScrapingRun:
        run = self.runs.get(run_id)
        if run is None:
            raise NotFoundError("Scraping run not found", code="SCRAPING_RUN_NOT_FOUND")
        return run

    def cancel_run(self, run_id: uuid.UUID) -> ScrapingRun:
        run = self.get_run(run_id)
        if run.status in FINAL_STATUSES:
            raise BusinessRuleError("This run is already finished", code="SCRAPING_RUN_FINISHED")
        run.status = ScrapingRunStatus.CANCELLED
        run.finished_at = utcnow()
        self.session.commit()
        return run

    # --- Exécution ---

    def execute_run(self, run_id: uuid.UUID) -> ScrapingRun:
        """Exécute une collecte PENDING (appelé par la tâche Celery)."""
        run = self.get_run(run_id)
        if run.status != ScrapingRunStatus.PENDING:
            logger.info("Run skipped", extra={"run_id": str(run.id), "status": run.status})
            return run
        source = run.source
        run.status = ScrapingRunStatus.RUNNING
        run.started_at = utcnow()
        self.session.commit()

        errors: list[str] = []
        try:
            adapter = self.scraper.build_adapter(source)
            try:
                pages = self.scraper.fetch(adapter)
                parsed = self.parser.parse(adapter, pages, get_settings().SCRAPER_MAX_JOBS_PER_RUN)
            finally:
                adapter.http.close()
            errors.extend(parsed.errors)
            if self.runs.current_status(run.id) == ScrapingRunStatus.CANCELLED:
                self.session.rollback()
                return self.get_run(run_id)
            run.jobs_found = len(parsed.jobs)

            result = JobIngestionService(self.session).ingest(
                parsed.jobs, source, origin=DataOrigin.SCRAPING
            )
            errors.extend(result.errors)
            run.jobs_created = result.created
            run.jobs_updated = result.updated
            run.jobs_duplicates = result.duplicates
            run.jobs_invalid = result.invalid
            run.status = ScrapingRunStatus.PARTIAL_SUCCESS if errors else ScrapingRunStatus.SUCCESS
            self.sources.record_run_result(source, success=True)
        except (ScrapingError, AppException) as exc:
            run, source = self._mark_failed(run_id, str(exc))
        except Exception as exc:
            # Une erreur inattendue ne doit jamais laisser la collecte bloquée en RUNNING.
            logger.exception("Unexpected scraping error", extra={"run_id": str(run_id)})
            run, source = self._mark_failed(run_id, f"Unexpected error: {type(exc).__name__}")

        run.finished_at = utcnow()
        run.details = {"errors": errors[:50]}
        AuditService(self.session).record(
            "scraping.run_finished", actor_type=ActorType.SYSTEM, entity_type="scraping_run",
            entity_id=run.id, details={"source": source.name, "status": run.status.value},
        )  # fmt: skip
        self.session.commit()
        self._after_run(run)
        return run

    def _mark_failed(self, run_id: uuid.UUID, message: str) -> tuple[ScrapingRun, Source]:
        self.session.rollback()
        run = self.get_run(run_id)
        run.status = ScrapingRunStatus.FAILED
        run.error_message = message[:2000]
        self.sources.record_run_result(run.source, success=False, error=run.error_message)
        return run, run.source

    def fail_stale_runs(self, older_than: timedelta = STALE_RUN_AFTER) -> int:
        """Collectes restées PENDING/RUNNING trop longtemps (worker redémarré...) -> FAILED."""
        count = self.runs.fail_stale(utcnow() - older_than, "Run interrupted (worker restarted?)")
        self.session.commit()
        return count

    def _after_run(self, run: ScrapingRun) -> None:
        payload = {
            "run_id": str(run.id),
            "source_id": str(run.source_id),
            "source_name": run.source_name,
            "status": run.status.value,
            "jobs_created": run.jobs_created,
        }
        publish_event(EventType.SCRAPING_RUN, payload)
        logger.info("Scraping run finished", extra=payload)
        if run.status == ScrapingRunStatus.FAILED:
            publish_event(EventType.SCRAPING_ERROR, payload | {"error": run.error_message})
            NotificationService(self.session).notify_admins(
                NotificationType.SCRAPING_ERROR,
                f"Échec de la collecte : {run.source_name}",
                run.error_message or "Erreur inconnue",
                data=payload,
            )

    def test_source(self, source_id: uuid.UUID) -> dict[str, Any]:
        """Collecte "à blanc" : FETCH + PARSE + NORMALIZE, sans rien enregistrer."""
        source: Source = self.sources.get(source_id)
        adapter = self.scraper.build_adapter(source)
        try:
            pages = self.scraper.fetch(adapter)
            parsed = self.parser.parse(adapter, pages, PREVIEW_SIZE)
        except ScrapingError as exc:
            raise BusinessRuleError(
                f"Source test failed: {exc}", code="SOURCE_TEST_FAILED"
            ) from exc
        finally:
            adapter.http.close()
        normalizer = NormalizerService(self.session)
        return {
            "pages_fetched": len(pages),
            "jobs_parsed": len(parsed.jobs),
            "preview": [normalizer.normalize(job) for job in parsed.jobs[:PREVIEW_SIZE]],
            "errors": parsed.errors,
        }

    # --- Collectes réalisées par n8n ---

    def record_external_run(
        self,
        source: Source,
        *,
        status: ScrapingRunStatus,
        execution_id: str | None,
        jobs_found: int = 0,
        jobs_created: int = 0,
        error_message: str | None = None,
        details: dict[str, Any] | None = None,
    ) -> ScrapingRun:
        """Enregistre le bilan d'une collecte faite par n8n (idempotent via execution_id)."""
        run = self.runs.get_by_external_execution(execution_id) if execution_id else None
        if run is None:
            run = self.runs.add(
                ScrapingRun(
                    source_id=source.id,
                    trigger=ScrapingTrigger.N8N,
                    external_execution_id=execution_id,
                    started_at=utcnow(),
                )
            )
        run.status = status
        run.jobs_found = jobs_found
        run.jobs_created = jobs_created
        run.error_message = error_message
        run.details = details or {}
        if status in FINAL_STATUSES:
            run.finished_at = utcnow()
            self.sources.record_run_result(
                source, success=status != ScrapingRunStatus.FAILED, error=error_message
            )
        self.session.commit()
        if status in FINAL_STATUSES:
            self._after_run(run)
        return run
