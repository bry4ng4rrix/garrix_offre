"""Candidature automatique : prépare (et, en mode « send », envoie) les candidatures aux offres
compatibles, selon les critères choisis par l'utilisateur.

Garde-fous :
- désactivée par défaut ; l'activation en mode « send » vaut accord explicite de l'utilisateur ;
- plafond quotidien (`daily_limit`) ;
- jamais deux candidatures pour la même offre, ni deux candidatures à la même entreprise en
  moins de 30 jours ;
- envoi uniquement par email (offres avec une adresse de candidature), avec un CV joint, et si
  l'envoi d'emails est configuré ; sinon la candidature reste « prête » et l'utilisateur la valide ;
- aucun formulaire de site n'est rempli automatiquement.
"""

import logging
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import Select, and_, exists, func, or_, select
from sqlalchemy.orm import Session

from app.core.exceptions import AppException, BusinessRuleError
from app.modules.applications.models import Application, AutoApplySettings
from app.modules.applications.schemas import (
    ApplicationCreate,
    AutoApplySettingsUpdate,
    PrepareRequest,
    SubmitRequest,
)
from app.modules.applications.service import ApplicationService
from app.modules.documents.service import DocumentService
from app.modules.integrations.email.service import EmailService
from app.modules.jobs.models import Job, JobSource, JobUserState
from app.modules.jobs.repository import VISIBLE_STATUSES, country_condition
from app.modules.matching.models import JobMatch
from app.modules.notifications.service import NotificationService
from app.modules.realtime.events import EventType, publish_event
from app.modules.sources.models import Source
from app.modules.users.models import User
from app.modules.users.repository import UserRepository
from app.shared.enums import (
    ApplicationStatus,
    AutoApplyMode,
    DocumentType,
    NotificationType,
)
from app.shared.utils import utcnow

logger = logging.getLogger("app.applications")

# Pas deux candidatures à la même entreprise sur cette période.
SAME_COMPANY_COOLDOWN_DAYS = 30


@dataclass
class RunReport:
    status: str = "done"
    sent: int = 0
    prepared: int = 0
    errors: int = 0
    items: list[dict[str, Any]] = field(default_factory=list)

    def as_dict(self) -> dict[str, Any]:
        return {
            "status": self.status,
            "sent": self.sent,
            "prepared": self.prepared,
            "errors": self.errors,
            "items": self.items,
        }


class AutoApplyService:
    def __init__(self, session: Session) -> None:
        self.session = session
        self.applications = ApplicationService(session)

    # --- Réglages ---

    def get_settings(self, user_id: uuid.UUID) -> AutoApplySettings:
        settings = self.session.scalar(
            select(AutoApplySettings).where(AutoApplySettings.user_id == user_id)
        )
        if settings is None:
            settings = AutoApplySettings(user_id=user_id)
            self.session.add(settings)
            self.session.flush()
        return settings

    def update_settings(self, user: User, data: AutoApplySettingsUpdate) -> AutoApplySettings:
        settings = self.get_settings(user.id)
        values = data.model_dump(exclude_unset=True)
        if values.get("cv_document_id"):
            document = DocumentService(self.session).get(user, values["cv_document_id"])
            if document.document_type != DocumentType.CV:
                raise BusinessRuleError("The document is not a CV", code="INVALID_DOCUMENT_TYPE")
        if "categories" in values:
            values["categories"] = [category.value for category in data.categories or []]
        for name, value in values.items():
            setattr(settings, name, value)
        self.session.commit()
        return settings

    def status(self, user: User) -> dict[str, Any]:
        settings = self.get_settings(user.id)
        self.session.commit()
        today_count, today_sent = self._today_counts(user.id)
        eligible = self.session.scalar(
            select(func.count()).select_from(self._candidates_query(user, settings).subquery())
        )
        return {
            "settings": settings,
            "email_configured": EmailService().is_configured,
            "today_count": today_count,
            "today_sent": today_sent,
            "remaining_today": max(0, settings.daily_limit - today_count),
            "eligible_jobs": eligible or 0,
        }

    # --- Exécution ---

    def run(self, user: User) -> RunReport:
        settings = self.get_settings(user.id)
        report = RunReport()
        if not settings.enabled:
            report.status = "disabled"
            return report
        today_count, _ = self._today_counts(user.id)
        remaining = settings.daily_limit - today_count
        if remaining <= 0:
            report.status = "limit_reached"
            return report

        email_ready = EmailService().is_configured
        send_mode = settings.mode == AutoApplyMode.SEND
        recent_companies = self._recent_companies(user.id)
        candidates = self.session.execute(
            self._candidates_query(user, settings).limit(remaining * 5)
        ).all()

        for job, score in candidates:
            if report.sent + report.prepared >= remaining:
                break
            if job.company_id and job.company_id in recent_companies:
                continue
            item = self._apply(user, settings, job, score, send_mode, email_ready)
            report.items.append(item)
            outcome = item["outcome"]
            if outcome == "sent":
                report.sent += 1
            elif outcome == "prepared":
                report.prepared += 1
            else:
                report.errors += 1
            if outcome != "error" and job.company_id:
                recent_companies.add(job.company_id)

        settings.last_run_at = utcnow()
        self.session.commit()
        self._announce(user, report)
        logger.info(
            "Auto-apply run finished",
            extra={"user_id": str(user.id), "sent": report.sent, "prepared": report.prepared,
                   "errors": report.errors},
        )  # fmt: skip
        return report

    def run_for_all(self) -> dict[str, int]:
        """Candidature automatique pour tous les utilisateurs qui l'ont activée (n8n)."""
        user_ids = self.session.scalars(
            select(AutoApplySettings.user_id).where(AutoApplySettings.enabled.is_(True))
        ).all()
        totals = {"users": 0, "sent": 0, "prepared": 0, "errors": 0}
        for user_id in user_ids:
            user = UserRepository(self.session).get(user_id)
            if user is None or not user.is_active:
                continue
            report = self.run(user)
            totals["users"] += 1
            totals["sent"] += report.sent
            totals["prepared"] += report.prepared
            totals["errors"] += report.errors
        return totals

    # --- Interne ---

    def _apply(
        self,
        user: User,
        settings: AutoApplySettings,
        job: Job,
        score: float | None,
        send_mode: bool,
        email_ready: bool,
    ) -> dict[str, Any]:
        item: dict[str, Any] = {
            "application_id": None,
            "job_id": job.id,
            "job_title": job.title,
            "company_name": job.company.name if job.company else None,
            "score": round(score) if score is not None else None,
            "outcome": "prepared",
            "detail": None,
        }
        try:
            application = self.applications.create(
                user,
                ApplicationCreate(
                    job_id=job.id,
                    status=ApplicationStatus.PREPARING,
                    cv_document_id=settings.cv_document_id,
                    notes="Candidature automatique",
                ),
                automatic=True,
            )
            item["application_id"] = application.id
            application = self.applications.prepare(
                user, application.id, PrepareRequest(), automatic=True
            )
        except AppException as exc:
            self.session.rollback()
            item.update(outcome="error", detail=exc.code)
            return item

        if not send_mode:
            item["detail"] = "Mode préparation : à valider"
        elif not email_ready:
            item["detail"] = "Envoi d'emails non configuré sur le serveur : à valider"
        elif not job.application_email:
            item["detail"] = "Pas d'adresse email : postulez sur le site de l'offre"
        elif application.cv_document_id is None:
            item["detail"] = "Aucun CV : ajoutez un CV pour l'envoi automatique"
        else:
            try:
                self.applications.submit(
                    user,
                    application.id,
                    SubmitRequest(confirm=True, send_email=True),
                    automatic=True,
                )
                item["outcome"] = "sent"
            except AppException as exc:
                self.session.rollback()
                item["detail"] = f"Envoi impossible ({exc.code}) : à valider"
        return item

    def _candidates_query(self, user: User, settings: AutoApplySettings) -> Select[Any]:
        """Offres compatibles, pas encore traitées, les plus intéressantes d'abord."""
        since = utcnow() - timedelta(days=settings.max_job_age_days)
        already_applied = exists().where(
            Application.user_id == user.id, Application.job_id == Job.id
        )
        ignored = exists().where(
            JobUserState.job_id == Job.id,
            JobUserState.user_id == user.id,
            JobUserState.is_ignored.is_(True),
        )
        stmt = (
            select(Job, JobMatch.score)
            .join(JobMatch, and_(JobMatch.job_id == Job.id, JobMatch.user_id == user.id))
            .where(
                JobMatch.score >= settings.min_score,
                Job.status.in_(VISIBLE_STATUSES),
                func.coalesce(Job.published_at, Job.created_at) >= since,
                ~already_applied,
                ~ignored,
                exists().where(
                    JobSource.job_id == Job.id,
                    JobSource.source_id == Source.id,
                    Source.category.in_(settings.categories),
                ),
            )
        )
        if settings.countries:
            stmt = stmt.where(country_condition(settings.countries))
        if settings.remote_only:
            stmt = stmt.where(Job.is_remote.is_(True))
        for keyword in settings.excluded_keywords:
            pattern = f"%{keyword}%"
            stmt = stmt.where(
                ~or_(Job.title.ilike(pattern), func.coalesce(Job.description, "").ilike(pattern))
            )
        ordering: list[Any] = []
        if settings.mode == AutoApplyMode.SEND:
            # Les offres envoyables par email passent devant.
            ordering.append(Job.application_email.is_(None))
        ordering += [JobMatch.score.desc(), func.coalesce(Job.published_at, Job.created_at).desc()]
        return stmt.order_by(*ordering)

    def _today_counts(self, user_id: uuid.UUID) -> tuple[int, int]:
        start = _start_of_day(utcnow())
        created = self.session.scalar(
            select(func.count()).where(
                Application.user_id == user_id,
                Application.is_automatic.is_(True),
                Application.created_at >= start,
            )
        )
        sent = self.session.scalar(
            select(func.count()).where(
                Application.user_id == user_id,
                Application.is_automatic.is_(True),
                Application.submitted_at >= start,
            )
        )
        return created or 0, sent or 0

    def _recent_companies(self, user_id: uuid.UUID) -> set[uuid.UUID]:
        since = utcnow() - timedelta(days=SAME_COMPANY_COOLDOWN_DAYS)
        rows = self.session.scalars(
            select(Job.company_id)
            .join(Application, Application.job_id == Job.id)
            .where(
                Application.user_id == user_id,
                Application.created_at >= since,
                Job.company_id.is_not(None),
            )
        ).all()
        return {company_id for company_id in rows if company_id}

    def _announce(self, user: User, report: RunReport) -> None:
        if not (report.sent or report.prepared):
            return
        parts = []
        if report.sent:
            parts.append(f"{report.sent} envoyée{'s' if report.sent > 1 else ''}")
        if report.prepared:
            parts.append(f"{report.prepared} à valider")
        titles = [item["job_title"] for item in report.items if item["outcome"] != "error"]
        data = {"automatic": True, "sent": report.sent, "prepared": report.prepared}
        publish_event(EventType.APPLICATION_STATUS, data, user.id)
        NotificationService(self.session).notify(
            user.id,
            NotificationType.APPLICATION_STATUS,
            f"Candidature automatique : {', '.join(parts)}",
            " · ".join(titles[:5]) + (" …" if len(titles) > 5 else ""),
            data=data,
        )


def _start_of_day(moment: datetime) -> datetime:
    return moment.replace(hour=0, minute=0, second=0, microsecond=0)
