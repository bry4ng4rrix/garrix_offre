"""Webhooks appelés par n8n : /api/v1/webhooks/n8n/...

Tous exigent l'en-tête `X-N8N-Webhook-Secret`. En-têtes optionnels :
- `Idempotency-Key` : rend l'appel idempotent (renvoyer deux fois = une seule action) ;
- `X-N8N-Workflow` / `X-N8N-Execution-Id` : tracés dans le monitoring.
"""

import logging
import uuid
from collections.abc import Callable
from typing import Any

from fastapi import APIRouter, Depends, status
from fastapi.responses import JSONResponse

from app.api.dependencies import DbSession
from app.modules.applications.schemas import FollowUpDue
from app.modules.applications.service import ApplicationService
from app.modules.integrations.n8n.dependencies import N8nContext, verify_n8n_secret
from app.modules.integrations.n8n.schemas import (
    ApplicationStatusIn,
    JobAlertEmailIn,
    JobAlertEmailResult,
    MonitoringAlertIn,
    N8nIngestionResult,
    N8nJobIn,
    N8nJobsIn,
    N8nSource,
    RecalculateAllResult,
    RecruiterResponseIn,
    RecruiterResponseResult,
    ScrapingStatusIn,
)
from app.modules.integrations.n8n.service import IdempotentReplay, N8nWebhookService
from app.modules.jobs.schemas import MaintenanceResult
from app.modules.jobs.service import JobService
from app.modules.monitoring.service import MonitoringService
from app.modules.notifications.service import NotificationService
from app.modules.scraping.router import queue_run
from app.modules.scraping.schemas import RunRequestResult
from app.modules.scraping.service import ScrapingService
from app.modules.sources.service import SourceService
from app.shared.enums import NotificationType, ScrapingTrigger
from app.shared.schemas import ApiResponse, error_responses, ok

router = APIRouter(
    prefix="/webhooks/n8n",
    tags=["n8n Webhooks"],
    dependencies=[Depends(verify_n8n_secret)],
    responses=error_responses(401, 422),
)
logger = logging.getLogger("app.n8n")


def _handle(session: DbSession, endpoint: str, context: Any, handler: Callable[[], Any]) -> Any:
    service = N8nWebhookService(session)
    try:
        return ok(service.run(endpoint, context, handler))
    except IdempotentReplay as replay:
        return JSONResponse(content=ok(replay.response), headers={"Idempotent-Replayed": "true"})


# --- Offres ---


@router.post(
    "/job",
    response_model=ApiResponse[N8nIngestionResult],
    summary="Recevoir une offre",
    description="Même pipeline que les collectes : normalisation, validation, déduplication, "
    "matching, notifications.",
)
def receive_job(payload: N8nJobIn, session: DbSession, context: N8nContext):
    batch = N8nJobsIn(
        source_id=payload.source_id,
        source_name=payload.source_name,
        jobs=[payload],
    )
    service = N8nWebhookService(session)
    return _handle(session, "job", context, lambda: service.ingest_jobs(batch))


@router.post(
    "/jobs",
    response_model=ApiResponse[N8nIngestionResult],
    summary="Recevoir un lot d'offres (max 500)",
    description="`high_matches` liste les nouvelles offres dont le score atteint le seuil de "
    "l'utilisateur ; `notification_delivery` indique qui envoie Telegram / Email.",
)
def receive_jobs(payload: N8nJobsIn, session: DbSession, context: N8nContext):
    service = N8nWebhookService(session)
    return _handle(session, "jobs", context, lambda: service.ingest_jobs(payload))


@router.post(
    "/job-alert-email",
    response_model=ApiResponse[JobAlertEmailResult],
    summary="Recevoir un email d'alerte d'offres",
    description="Pour les sites sans API ni flux autorisé (LinkedIn, Indeed, APEC, Malt...) : "
    "n8n transmet les emails d'alerte que vous recevez ; la source est reconnue par le domaine "
    "de l'expéditeur et les offres (titre + lien) sont extraites puis ingérées. Aucune page "
    "du site n'est visitée. Utilisez Idempotency-Key = Message-ID de l'email.",
)
def job_alert_email(payload: JobAlertEmailIn, session: DbSession, context: N8nContext):
    service = N8nWebhookService(session)
    return _handle(session, "job-alert-email", context, lambda: service.ingest_alert_email(payload))


@router.post(
    "/scraping-status",
    response_model=ApiResponse[dict[str, Any]],
    summary="Bilan d'une collecte faite par n8n",
    description="Enregistre l'exécution (idempotent via execution_id) ; un échec notifie les admins.",
)
def scraping_status(payload: ScrapingStatusIn, session: DbSession, context: N8nContext):
    service = N8nWebhookService(session)
    return _handle(
        session, "scraping-status", context, lambda: service.record_scraping_status(payload)
    )


@router.get(
    "/sources",
    response_model=ApiResponse[list[N8nSource]],
    summary="Sources à collecter",
    description="Sources actives avec collecte activée. `fetch_mode=backend` : appeler "
    "POST /webhooks/n8n/sources/{id}/run ; `fetch_mode=n8n` : n8n lit la source puis envoie "
    "les offres sur POST /webhooks/n8n/jobs.",
)
def list_sources(session: DbSession):
    return ok(SourceService(session).list_collectable())


@router.post(
    "/sources/{source_id}/run",
    response_model=ApiResponse[RunRequestResult],
    status_code=status.HTTP_202_ACCEPTED,
    summary="Lancer la collecte backend d'une source",
    responses=error_responses(404, 503),
)
def run_source(source_id: uuid.UUID, session: DbSession, context: N8nContext):
    return _handle(
        session,
        "sources.run",
        context,
        lambda: queue_run(ScrapingService(session), source_id, ScrapingTrigger.N8N),
    )


@router.post(
    "/maintenance/expire-jobs",
    response_model=ApiResponse[MaintenanceResult],
    summary="Expirer / archiver les anciennes offres",
)
def expire_jobs(session: DbSession, context: N8nContext):
    return _handle(
        session,
        "maintenance.expire-jobs",
        context,
        lambda: JobService(session).expire_outdated_jobs(),
    )


# --- Matching ---


@router.post(
    "/matching/recalculate",
    response_model=ApiResponse[RecalculateAllResult],
    status_code=status.HTTP_202_ACCEPTED,
    summary="Recalculer le matching de tous les utilisateurs",
)
def recalculate_matching(session: DbSession, context: N8nContext):
    def handler() -> dict[str, Any]:
        from app.modules.matching.tasks import recalculate_all_matches

        try:
            recalculate_all_matches.delay()
            return {"status": "queued"}
        except Exception as exc:  # noqa: BLE001 - broker indisponible : calcul direct
            logger.warning("Matching task not queued: %s", type(exc).__name__)
            return {"status": "done", "jobs_matched": recalculate_all_matches()}

    return _handle(session, "matching.recalculate", context, handler)


# --- Candidatures ---


@router.post(
    "/application-status",
    response_model=ApiResponse[dict[str, Any]],
    summary="Signaler un changement de statut de candidature",
    description="Événements externes uniquement : follow_up, interview, offer, rejected. "
    "n8n ne peut jamais marquer une candidature comme envoyée (validation de l'utilisateur requise).",
    responses=error_responses(404),
)
def application_status(payload: ApplicationStatusIn, session: DbSession, context: N8nContext):
    service = N8nWebhookService(session)
    return _handle(
        session, "application-status", context, lambda: service.change_application_status(payload)
    )


@router.get(
    "/applications/follow-ups-due",
    response_model=ApiResponse[list[FollowUpDue]],
    summary="Candidatures à relancer",
    description="Envoyées, sans réponse, dont la date de relance est passée.",
)
def follow_ups_due(session: DbSession):
    applications = ApplicationService(session).follow_ups_due()
    return ok(
        [
            {
                "application_id": item.id,
                "user_id": item.user_id,
                "job_title": item.job_title,
                "company_name": item.company_name,
                "submitted_at": item.submitted_at,
                "follow_up_at": item.follow_up_at,
            }
            for item in applications
        ]
    )


@router.post(
    "/recruiter-response",
    response_model=ApiResponse[RecruiterResponseResult],
    summary="Recevoir une réponse de recruteur (email lu par n8n)",
    description="Associe la réponse à une candidature (application_id ou corrélation contrôlée), "
    "l'analyse, l'enregistre et notifie. Idempotent via message_id.",
)
def recruiter_response(payload: RecruiterResponseIn, session: DbSession, context: N8nContext):
    service = N8nWebhookService(session)
    return _handle(
        session, "recruiter-response", context, lambda: service.receive_recruiter_response(payload)
    )


# --- Monitoring ---


@router.get(
    "/monitoring/summary",
    response_model=ApiResponse[dict[str, Any]],
    summary="Résumé pour le rapport quotidien",
)
def monitoring_summary(session: DbSession):
    return ok(MonitoringService(session).daily_summary())


@router.post(
    "/monitoring-alert",
    response_model=ApiResponse[dict[str, Any]],
    summary="Remonter une alerte détectée par n8n",
    description="Crée une notification `monitoring` pour les administrateurs.",
)
def monitoring_alert(payload: MonitoringAlertIn, session: DbSession, context: N8nContext):
    def handler() -> dict[str, Any]:
        notifications = NotificationService(session).notify_admins(
            NotificationType.MONITORING, payload.title, payload.message, {"level": payload.level}
        )
        return {"notified": len(notifications)}

    return _handle(session, "monitoring-alert", context, handler)
