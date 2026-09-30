"""Traitement des appels n8n -> FastAPI.

n8n orchestre (planification, lecture des emails, envoi Telegram...) ; toute la logique
métier reste ici, dans FastAPI (RG-13). Ce service :
- retrouve la source des offres reçues ;
- délègue au bon service métier (pipeline d'ingestion, candidatures, réponses...) ;
- journalise chaque appel et gère l'idempotence (en-tête Idempotency-Key).
"""

import logging
import time
from collections.abc import Callable
from typing import Any

from fastapi.encoders import jsonable_encoder
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.exceptions import AppException, NotFoundError
from app.modules.applications.repository import ApplicationRepository
from app.modules.applications.responses import RecruiterResponseService
from app.modules.applications.service import ApplicationService
from app.modules.audit.service import AuditService
from app.modules.integrations.n8n.dependencies import WebhookContext
from app.modules.integrations.n8n.models import N8nWebhookEvent
from app.modules.integrations.n8n.repository import N8nWebhookEventRepository
from app.modules.integrations.n8n.schemas import (
    ApplicationStatusIn,
    JobAlertEmailIn,
    N8nJobsIn,
    RecruiterResponseIn,
    ScrapingStatusIn,
    SourceReference,
)
from app.modules.scraping.email_alerts import JobAlertEmailParser
from app.modules.scraping.pipeline import JobIngestionService
from app.modules.scraping.schemas import JobPayload
from app.modules.scraping.service import ScrapingService
from app.modules.sources.models import Source
from app.modules.sources.repository import SourceRepository
from app.modules.sources.service import DEFAULT_WEBHOOK_SOURCE, SourceService
from app.modules.users.repository import UserRepository
from app.shared.enums import ActorType, DataOrigin, SourceType

logger = logging.getLogger("app.n8n")


class IdempotentReplay(Exception):
    """La requête a déjà été traitée : on renvoie la réponse enregistrée."""

    def __init__(self, response: dict[str, Any]) -> None:
        self.response = response


class N8nWebhookService:
    def __init__(self, session: Session) -> None:
        self.session = session
        self.events = N8nWebhookEventRepository(session)

    # --- Idempotence + journal ---

    def run(
        self, endpoint: str, context: WebhookContext, handler: Callable[[], Any]
    ) -> dict[str, Any]:
        """Exécute `handler` une seule fois par Idempotency-Key et journalise l'appel."""
        if context.idempotency_key:
            previous = self.events.get_success(endpoint, context.idempotency_key)
            if previous is not None:
                logger.info("Idempotent replay", extra={"endpoint": endpoint})
                raise IdempotentReplay(previous.response or {})

        started = time.perf_counter()
        try:
            result = jsonable_encoder(handler())
        except AppException as exc:
            self.session.rollback()
            self._log(endpoint, context, "error", started, error_code=exc.code)
            raise
        self._log(endpoint, context, "success", started, response=result)
        return result

    def _log(
        self,
        endpoint: str,
        context: WebhookContext,
        status: str,
        started: float,
        *,
        response: dict[str, Any] | None = None,
        error_code: str | None = None,
    ) -> None:
        # Une clé déjà utilisée par un appel en échec peut être réutilisée pour un nouvel essai.
        key = context.idempotency_key
        if key and (existing := self.events.get_by_key(endpoint, key)) is not None:
            self.events.delete(existing)
        event = N8nWebhookEvent(
            endpoint=endpoint,
            idempotency_key=key,
            workflow_name=context.workflow_name,
            execution_id=context.execution_id,
            status=status,
            error_code=error_code,
            summary=_summary(response),
            response=response,
            duration_ms=int((time.perf_counter() - started) * 1000),
        )
        self.session.add(event)
        AuditService(self.session).record(
            "webhook.received", actor_type=ActorType.N8N, entity_type="n8n_webhook",
            entity_id=endpoint, details={"status": status, "workflow": context.workflow_name},
        )  # fmt: skip
        try:
            self.session.commit()
        except IntegrityError:
            self.session.rollback()  # appel concurrent avec la même clé : déjà journalisé
        logger.info(
            "n8n webhook handled",
            extra={"endpoint": endpoint, "status": status, "workflow": context.workflow_name},
        )

    # --- Traitements ---

    def resolve_source(self, reference: SourceReference) -> Source:
        repository = SourceRepository(self.session)
        if reference.source_id:
            source = repository.get(reference.source_id)
            if source is None:
                raise NotFoundError("Source not found", code="SOURCE_NOT_FOUND")
            return source
        if reference.source_name:
            source = repository.get_by_name(reference.source_name)
            if source is None:
                raise NotFoundError("Source not found", code="SOURCE_NOT_FOUND")
            return source
        return SourceService(self.session).get_or_create_default(
            DEFAULT_WEBHOOK_SOURCE, SourceType.WEBHOOK
        )

    def ingest_jobs(self, data: N8nJobsIn) -> dict[str, Any]:
        source = self.resolve_source(data)
        result = JobIngestionService(self.session).ingest(
            data.jobs, source, origin=DataOrigin.N8N, notify=data.notify
        )
        return result.model_dump() | {
            "notification_delivery": get_settings().NOTIFICATION_DELIVERY_MODE
        }

    def ingest_alert_email(self, data: JobAlertEmailIn) -> dict[str, Any]:
        """Offres extraites d'un email d'alerte (sites sans API ni flux autorisé)."""
        sources = list(
            self.session.scalars(SourceRepository(self.session).list_query(enabled=True))
        )
        extraction = JobAlertEmailParser(sources).extract(
            str(data.sender_email), data.html, data.text, data.source_name
        )
        source = extraction.source or SourceService(self.session).get_or_create_default(
            DEFAULT_WEBHOOK_SOURCE, SourceType.WEBHOOK
        )
        payloads = [JobPayload.model_validate(job) for job in extraction.jobs]
        result = JobIngestionService(self.session).ingest(
            payloads, source, origin=DataOrigin.N8N, notify=data.notify
        )
        return result.model_dump() | {
            "notification_delivery": get_settings().NOTIFICATION_DELIVERY_MODE,
            "source": source.name,
            "extracted": len(payloads),
        }

    def record_scraping_status(self, data: ScrapingStatusIn) -> dict[str, Any]:
        source = self.resolve_source(data)
        run = ScrapingService(self.session).record_external_run(
            source,
            status=data.status,
            execution_id=data.execution_id,
            jobs_found=data.jobs_found,
            jobs_created=data.jobs_created,
            error_message=data.error_message,
            details=data.details,
        )
        return {"run_id": run.id, "status": run.status}

    def change_application_status(self, data: ApplicationStatusIn) -> dict[str, Any]:
        application = ApplicationRepository(self.session).get(data.application_id)
        if application is None:
            raise NotFoundError("Application not found", code="APPLICATION_NOT_FOUND")
        application = ApplicationService(self.session).change_status(
            application, data.status, actor_type=ActorType.N8N, actor_id=None, note=data.note
        )
        return {"application_id": application.id, "status": application.status}

    def receive_recruiter_response(self, data: RecruiterResponseIn) -> dict[str, Any]:
        user = (
            UserRepository(self.session).get_by_email(str(data.user_email))
            if data.user_email
            else None
        )
        received = RecruiterResponseService(self.session).receive(
            sender_email=str(data.sender_email),
            sender_name=data.sender_name,
            subject=data.subject,
            body=data.body,
            received_at=data.received_at,
            application_id=data.application_id,
            message_id=data.message_id,
            user=user,
        )
        response = received.response
        return {
            "response_id": response.id,
            "application_id": response.application_id,
            "correlation_method": response.correlation_method,
            "response_type": response.response_type,
            "duplicate": received.duplicate,
        }


def _summary(response: dict[str, Any] | None) -> dict[str, Any]:
    """Petit résumé chiffré de la réponse (pour le monitoring), sans données personnelles."""
    if not response:
        return {}
    keys = ("received", "created", "updated", "duplicates", "invalid", "status", "duplicate")
    return {key: response[key] for key in keys if key in response}
