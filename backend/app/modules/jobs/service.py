import logging
import uuid
from datetime import timedelta
from typing import Any

from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.exceptions import BusinessRuleError, NotFoundError
from app.modules.jobs.models import Job, JobSkill, JobUserState
from app.modules.jobs.repository import JobFilters, JobRepository, JobUserStateRepository
from app.modules.jobs.schemas import JobStateUpdate, JobUpdate
from app.modules.matching.models import JobMatch
from app.modules.matching.repository import JobMatchRepository
from app.modules.skills.service import SkillCatalogService
from app.modules.users.models import User
from app.shared.enums import ApplicationStatus, JobStatus
from app.shared.pagination import PaginationParams
from app.shared.utils import truncate, utcnow

logger = logging.getLogger("app.jobs")

EXCERPT_LENGTH = 280

# Transitions autorisées du cycle de vie d'une offre (UML 17).
JOB_STATUS_TRANSITIONS: dict[JobStatus, set[JobStatus]] = {
    JobStatus.NEW: {JobStatus.ACTIVE, JobStatus.EXPIRED, JobStatus.ARCHIVED},
    JobStatus.ACTIVE: {JobStatus.EXPIRED, JobStatus.ARCHIVED},
    JobStatus.EXPIRED: {JobStatus.ACTIVE, JobStatus.ARCHIVED},  # ACTIVE : l'offre réapparaît
    JobStatus.ARCHIVED: set(),
}


class JobService:
    """Consultation et gestion des offres normalisées."""

    def __init__(self, session: Session) -> None:
        self.session = session
        self.jobs = JobRepository(session)
        self.states = JobUserStateRepository(session)
        self.matches = JobMatchRepository(session)

    # --- Lecture ---

    def list_jobs(
        self,
        user: User,
        filters: JobFilters,
        pagination: PaginationParams,
        include_description: bool = False,
    ) -> tuple[list[dict[str, Any]], int]:
        jobs, total = self.jobs.paginate(self.jobs.search_query(user.id, filters), pagination)
        return self._to_reads(user, jobs, include_description), total

    def country_counts(self, user: User, filters: JobFilters) -> list[dict[str, Any]]:
        return [
            {"country": country, "count": count}
            for country, count in self.jobs.country_counts(user.id, filters)
        ]

    def get_job(self, user: User, job_id: uuid.UUID, mark_seen: bool = True) -> dict[str, Any]:
        job = self._get(job_id)
        if mark_seen:
            state = self.states.get_or_create(user.id, job.id)
            if state.seen_at is None:
                state.seen_at = utcnow()
                self.session.commit()
        return self._to_reads(user, [job], include_description=True)[0]

    def get_raw(self, job_id: uuid.UUID) -> dict[str, Any]:
        job = self._get(job_id)
        return {
            "id": job.id,
            "raw_data": job.raw_data,
            "normalized_data": job.normalized_data,
            "quality_issues": job.quality_issues,
            "sources": [
                _source_info(link.source, link.url, link.external_id) for link in job.sources
            ],
        }

    # --- État utilisateur (vue, sauvegardée, ignorée) ---

    def update_state(self, user: User, job_id: uuid.UUID, data: JobStateUpdate) -> dict[str, Any]:
        job = self._get(job_id)
        state = self.states.get_or_create(user.id, job.id)
        if data.is_saved is not None:
            state.is_saved = data.is_saved
        if data.is_ignored is not None:
            state.is_ignored = data.is_ignored
        if data.seen is not None:
            state.seen_at = utcnow() if data.seen else None
        self.session.commit()
        return self._to_reads(user, [job], include_description=False)[0]

    # --- Administration ---

    def update_job(self, job_id: uuid.UUID, data: JobUpdate) -> Job:
        job = self._get(job_id)
        updates = data.model_dump(exclude_unset=True)
        new_status = updates.pop("status", None)
        if new_status is not None and new_status != job.status:
            self._check_transition(JobStatus(job.status), JobStatus(new_status))
            job.status = new_status
        skills = updates.pop("skills", None)
        if skills is not None:
            catalog = SkillCatalogService(self.session)
            job.skills = [
                JobSkill(skill=catalog.get_or_create(item["name"]), requirement=item["requirement"])
                for item in skills
            ]
        for field, value in updates.items():
            setattr(job, field, value)
        self.session.commit()
        return job

    def delete_job(self, job_id: uuid.UUID) -> None:
        self.jobs.delete(self._get(job_id))
        self.session.commit()

    def expire_outdated_jobs(self) -> dict[str, int]:
        """Maintenance (déclenchée par n8n) : ACTIVE -> EXPIRED -> ARCHIVED selon l'âge."""
        settings = get_settings()
        now = utcnow()
        expired = self.jobs.expire_outdated(
            now, now - timedelta(days=settings.JOB_STALE_AFTER_DAYS)
        )
        archived = self.jobs.archive_expired(now - timedelta(days=settings.JOB_ARCHIVE_AFTER_DAYS))
        self.session.commit()
        logger.info("Job maintenance done", extra={"expired": expired, "archived": archived})
        return {"expired": expired, "archived": archived}

    # --- Construction de la réponse normalisée ---

    def build_read(self, user: User, job: Job) -> dict[str, Any]:
        return self._to_reads(user, [job], include_description=True)[0]

    def _to_reads(
        self, user: User, jobs: list[Job], include_description: bool
    ) -> list[dict[str, Any]]:
        job_ids = [job.id for job in jobs]
        matches = self.matches.get_for_jobs(user.id, job_ids)
        states = self.jobs.get_states(user.id, job_ids)
        applications = self.jobs.get_active_applications(user.id, job_ids)
        return [
            _job_to_read(
                job,
                matches.get(job.id),
                states.get(job.id),
                applications.get(job.id),
                include_description,
            )
            for job in jobs
        ]

    def _get(self, job_id: uuid.UUID) -> Job:
        job = self.jobs.get(job_id)
        if job is None:
            raise NotFoundError("Job not found", code="JOB_NOT_FOUND")
        return job

    @staticmethod
    def _check_transition(current: JobStatus, target: JobStatus) -> None:
        if target not in JOB_STATUS_TRANSITIONS[current]:
            raise BusinessRuleError(
                f"Job status cannot change from {current.value} to {target.value}",
                code="INVALID_JOB_STATUS_TRANSITION",
            )


def _source_info(source: Any, url: str | None, external_id: str | None) -> dict[str, Any]:
    return {
        "id": source.id if source else None,
        "name": source.name if source else None,
        "category": source.category if source else None,
        "url": url,
        "external_id": external_id,
    }


def _job_to_read(
    job: Job,
    match: JobMatch | None,
    state: JobUserState | None,
    application: tuple[uuid.UUID, ApplicationStatus] | None,
    include_description: bool,
) -> dict[str, Any]:
    """Transforme une offre en bloc JSON "normalisé" (format attendu par Flutter)."""
    company = job.company
    recruiter = job.recruiter
    is_ignored = bool(state and state.is_ignored)
    return {
        "id": job.id,
        "title": job.title,
        "excerpt": truncate(job.description, EXCERPT_LENGTH),
        "description": job.description if include_description else None,
        "source": _source_info(job.source, job.source_url, job.external_id),
        "other_sources": [
            _source_info(link.source, link.url, link.external_id)
            for link in job.sources
            if link.source_id != job.source_id
        ],
        "company": {
            "id": company.id if company else None,
            "name": company.name if company else None,
            "website": company.website if company else None,
            "logo_url": company.logo_url if company else None,
            "address": {
                "street": company.address if company else None,
                "postal_code": company.postal_code if company else None,
                "city": company.city if company else None,
                "country": company.country if company else None,
            },
            "contact": {
                "email": company.email if company else None,
                "phone": company.phone if company else None,
            },
        },
        "recruiter": {
            "id": recruiter.id if recruiter else None,
            "name": recruiter.display_name if recruiter else None,
            "job_title": recruiter.job_title if recruiter else None,
            "email": recruiter.email if recruiter else None,
            "phone": recruiter.phone if recruiter else None,
            "linkedin": recruiter.linkedin_url if recruiter else None,
            "website": recruiter.website if recruiter else None,
            "contact_source": recruiter.contact_source if recruiter else None,
        },
        "location": {
            "raw": job.location,
            "city": job.city,
            "country": job.country,
            "remote": job.is_remote,
            "hybrid": job.is_hybrid,
        },
        "contract": {"type": job.contract_type, "work_time": job.work_time},
        "salary": {
            "min": job.salary_min,
            "max": job.salary_max,
            "currency": job.salary_currency,
            "period": job.salary_period,
            "raw": job.salary_raw,
        },
        "experience": {"level": job.experience_level, "min_years": job.min_years_experience},
        "skills": [
            {
                "name": item.skill.name,
                "category": item.skill.category_code,
                "requirement": item.requirement,
            }
            for item in job.skills
        ],
        "languages": job.languages,
        "matching": (
            {
                "score": match.score,
                "matched_skills": match.matched_skills,
                "missing_skills": match.missing_skills,
                "reasons": match.reasons,
                "computed_at": match.computed_at,
            }
            if match
            else None
        ),
        "application": {"url": job.application_url, "email": job.application_email},
        "status": {
            "state": "ignored" if is_ignored else JobStatus(job.status).value,
            "is_new": not (state and state.seen_at) and not job.is_expired,
            "is_expired": job.is_expired,
            "is_saved": bool(state and state.is_saved),
            "is_ignored": is_ignored,
            "application_status": application[1] if application else ApplicationStatus.NOT_APPLIED,
            "application_id": application[0] if application else None,
        },
        "quality_issues": job.quality_issues,
        "published_at": job.published_at,
        "expires_at": job.expires_at,
        "scraped_at": job.scraped_at,
        "last_checked_at": job.last_checked_at,
        "created_at": job.created_at,
    }
