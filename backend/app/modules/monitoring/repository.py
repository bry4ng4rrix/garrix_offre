"""Requêtes de statistiques (lecture seule, sur les tables des autres modules)."""

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import Select, func, select
from sqlalchemy.orm import Session

from app.modules.applications.models import Application, RecruiterResponse
from app.modules.jobs.models import Job, JobSource
from app.modules.matching.models import JobMatch
from app.modules.scraping.models import ScrapingRun
from app.modules.sources.models import Source
from app.shared.enums import ApplicationStatus, JobStatus, ScrapingRunStatus


class MonitoringRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def _count(self, stmt: Select[Any]) -> int:
        return int(self.session.scalar(stmt) or 0)

    # --- Offres ---

    def jobs_seen_since(self, since: datetime) -> int:
        """Apparitions d'offres (y compris doublons) : "offres trouvées"."""
        return self._count(
            select(func.count()).select_from(JobSource).where(JobSource.last_seen_at >= since)
        )

    def jobs_created_since(self, since: datetime) -> int:
        return self._count(select(func.count()).select_from(Job).where(Job.created_at >= since))

    def jobs_by_status(self) -> dict[str, int]:
        stmt = select(Job.status, func.count()).group_by(Job.status)
        return {str(status): count for status, count in self.session.execute(stmt)}

    # --- Matching ---

    def matches_computed_since(self, user_id: uuid.UUID, since: datetime) -> int:
        stmt = (
            select(func.count())
            .select_from(JobMatch)
            .where(JobMatch.user_id == user_id, JobMatch.computed_at >= since)
        )
        return self._count(stmt)

    def matching_jobs(
        self, user_id: uuid.UUID, threshold: int, since: datetime | None = None
    ) -> int:
        stmt = (
            select(func.count())
            .select_from(JobMatch)
            .join(Job, Job.id == JobMatch.job_id)
            .where(
                JobMatch.user_id == user_id,
                JobMatch.score >= threshold,
                Job.status.in_([JobStatus.NEW, JobStatus.ACTIVE]),
            )
        )
        if since:
            stmt = stmt.where(Job.created_at >= since)
        return self._count(stmt)

    # --- Candidatures ---

    def applications_by_status(self, user_id: uuid.UUID) -> dict[str, int]:
        stmt = (
            select(Application.status, func.count())
            .where(Application.user_id == user_id)
            .group_by(Application.status)
        )
        return {str(status): count for status, count in self.session.execute(stmt)}

    def applications_submitted_since(self, user_id: uuid.UUID, since: datetime) -> list[datetime]:
        stmt = select(Application.submitted_at).where(
            Application.user_id == user_id, Application.submitted_at >= since
        )
        return [value for value in self.session.scalars(stmt) if value]

    def response_delays_days(self, user_id: uuid.UUID) -> list[float]:
        stmt = select(Application.submitted_at, Application.response_received_at).where(
            Application.user_id == user_id,
            Application.submitted_at.is_not(None),
            Application.response_received_at.is_not(None),
        )
        return [
            max((received - submitted).total_seconds() / 86400, 0)
            for submitted, received in self.session.execute(stmt)
            if submitted and received
        ]

    def count_submitted_ever(self, user_id: uuid.UUID) -> int:
        stmt = (
            select(func.count())
            .select_from(Application)
            .where(Application.user_id == user_id, Application.submitted_at.is_not(None))
        )
        return self._count(stmt)

    def count_with_response(self, user_id: uuid.UUID) -> int:
        stmt = (
            select(func.count())
            .select_from(Application)
            .where(
                Application.user_id == user_id,
                Application.submitted_at.is_not(None),
                Application.response_received_at.is_not(None),
            )
        )
        return self._count(stmt)

    def responses_since(self, user_id: uuid.UUID, since: datetime | None = None) -> int:
        stmt = (
            select(func.count())
            .select_from(RecruiterResponse)
            .where(RecruiterResponse.user_id == user_id)
        )
        if since:
            stmt = stmt.where(RecruiterResponse.received_at >= since)
        return self._count(stmt)

    def interviews_and_offers(self, user_id: uuid.UUID) -> tuple[int, int]:
        by_status = self.applications_by_status(user_id)
        return by_status.get(ApplicationStatus.INTERVIEW.value, 0), by_status.get(
            ApplicationStatus.OFFER.value, 0
        )

    # --- Collectes ---

    def failed_runs_since(self, since: datetime) -> int:
        stmt = (
            select(func.count())
            .select_from(ScrapingRun)
            .where(ScrapingRun.status == ScrapingRunStatus.FAILED, ScrapingRun.created_at >= since)
        )
        return self._count(stmt)

    def runs_by_status_since(self, since: datetime) -> dict[str, int]:
        stmt = (
            select(ScrapingRun.status, func.count())
            .where(ScrapingRun.created_at >= since)
            .group_by(ScrapingRun.status)
        )
        return {str(status): count for status, count in self.session.execute(stmt)}

    def source_stats_since(self, since: datetime) -> list[dict[str, object]]:
        runs = (
            select(
                ScrapingRun.source_id,
                func.count().label("runs"),
                func.count().filter(ScrapingRun.status == ScrapingRunStatus.FAILED).label("failed"),
                func.coalesce(func.sum(ScrapingRun.jobs_created), 0).label("jobs_created"),
            )
            .where(ScrapingRun.created_at >= since)
            .group_by(ScrapingRun.source_id)
            .subquery()
        )
        stmt = (
            select(Source, runs.c.runs, runs.c.failed, runs.c.jobs_created)
            .outerjoin(runs, runs.c.source_id == Source.id)
            .order_by(Source.priority.desc(), Source.name)
        )
        return [
            {
                "source_id": source.id,
                "name": source.name,
                "type": source.type,
                "enabled": source.enabled,
                "scraping_enabled": source.scraping_enabled,
                "last_run_at": source.last_run_at,
                "last_success_at": source.last_success_at,
                "last_error": source.last_error,
                "runs_7d": runs_count or 0,
                "failed_runs_7d": failed or 0,
                "jobs_created_7d": int(jobs_created or 0),
            }
            for source, runs_count, failed, jobs_created in self.session.execute(stmt)
        ]

    def recent_runs(self, limit: int = 10) -> list[ScrapingRun]:
        stmt = select(ScrapingRun).order_by(ScrapingRun.created_at.desc()).limit(limit)
        return list(self.session.scalars(stmt))

    def database_size_bytes(self) -> int | None:
        try:
            return int(
                self.session.scalar(select(func.pg_database_size(func.current_database()))) or 0
            )
        except Exception:  # noqa: BLE001 - information facultative (droits, autre SGBD)
            return None
