"""Pipeline d'ingestion des offres (RG-08) :

    NORMALIZE -> VALIDATE -> DEDUPLICATE -> SAVE -> MATCH -> NOTIFY

Utilisé par :
- les collectes lancées par le backend (ScrapingService, après FETCH et PARSE) ;
- les webhooks n8n (POST /webhooks/n8n/job et /jobs) ;
- la saisie manuelle (POST /jobs).

Chaque offre est traitée dans un "savepoint" : une offre en erreur n'empêche pas
l'enregistrement des autres (RG-19).
"""

import logging
from dataclasses import dataclass, field

from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.modules.companies.models import Company
from app.modules.companies.service import CompanyService
from app.modules.jobs.models import Job, JobSkill, JobSource
from app.modules.matching.service import MatchingService, ScoredJob
from app.modules.notifications.service import NotificationService
from app.modules.realtime.events import EventType, publish_event
from app.modules.recruiters.models import Recruiter
from app.modules.recruiters.service import RecruiterService
from app.modules.scraping.deduplication import DeduplicationService
from app.modules.scraping.normalizer import NormalizerService
from app.modules.scraping.schemas import IngestionResult, JobPayload, NormalizedJob
from app.modules.scraping.validator import JobValidator, ValidationOutcome
from app.modules.skills.service import SkillCatalogService
from app.modules.sources.models import Source
from app.modules.users.repository import UserRepository
from app.shared.enums import DataOrigin, JobStatus, NotificationType, SourceCategory
from app.shared.utils import normalize_text, utcnow

logger = logging.getLogger("app.scraping")

MAX_HIGH_MATCH_NOTIFICATIONS = 10
MAX_ERRORS_KEPT = 50


@dataclass
class _Processed:
    job: Job
    created: bool
    duplicate_method: str | None = None


@dataclass
class _Batch:
    created: list[Job] = field(default_factory=list)
    updated: list[Job] = field(default_factory=list)


class JobIngestionService:
    """Enregistre des offres collectées puis calcule le matching et notifie."""

    def __init__(self, session: Session) -> None:
        self.session = session
        self.normalizer = NormalizerService(session)
        self.validator = JobValidator()
        self.deduplication = DeduplicationService(session)
        self.companies = CompanyService(session)
        self.recruiters = RecruiterService(session)
        self.catalog = SkillCatalogService(session)

    def ingest(
        self,
        payloads: list[JobPayload],
        source: Source,
        *,
        origin: DataOrigin,
        created_by_id: object | None = None,
        notify: bool = True,
    ) -> IngestionResult:
        result = IngestionResult(received=len(payloads))
        batch = _Batch()

        for index, payload in enumerate(payloads):
            normalized = self.normalizer.normalize(payload)
            if normalized.contract_type is None and source.category == SourceCategory.CLIENTS:
                normalized.contract_type = (
                    "freelance"  # une mission de client est une mission freelance
                )
            outcome = self.validator.validate(normalized)
            if not outcome.is_valid:
                result.invalid += 1
                self._keep_error(
                    result, f"#{index} '{payload.title[:60]}': {', '.join(outcome.errors)}"
                )
                continue
            try:
                with self.session.begin_nested():
                    processed = self._save(normalized, outcome, source, origin, created_by_id)
            except SQLAlchemyError as exc:
                result.invalid += 1
                self._keep_error(result, f"#{index} '{payload.title[:60]}': database error")
                logger.warning(
                    "Job not saved: %s", type(exc).__name__, extra={"source": source.name}
                )
                continue

            result.job_ids.append(processed.job.id)
            if processed.created:
                result.created += 1
                result.created_job_ids.append(processed.job.id)
                batch.created.append(processed.job)
            else:
                result.duplicates += 1
                result.updated += 1
                batch.updated.append(processed.job)
        self.session.commit()

        # MATCH : nouvelles offres et offres mises à jour ; NOTIFY : nouvelles seulement.
        high_matches = MatchingService(self.session).match_jobs_for_all_users(
            batch.created + batch.updated
        )
        created_ids = {job.id for job in batch.created}
        for user_id, scored_jobs in high_matches.items():
            for scored in scored_jobs:
                if scored.job.id in created_ids:
                    result.high_matches.append(
                        {
                            "user_id": str(user_id),
                            "job_id": str(scored.job.id),
                            "score": scored.result.score,
                        }
                    )
        if notify:
            self._notify(high_matches, batch.created)

        logger.info(
            "Jobs ingested",
            extra={
                "source": source.name,
                "received": result.received,
                "created": result.created,
                "duplicates": result.duplicates,
                "invalid": result.invalid,
            },
        )
        return result

    # --- SAVE ---

    def _save(
        self,
        job_data: NormalizedJob,
        outcome: ValidationOutcome,
        source: Source,
        origin: DataOrigin,
        created_by_id: object | None,
    ) -> _Processed:
        company = self._company(job_data, source, origin)
        duplicate = self.deduplication.find_duplicate(
            job_data, source.id, company.id if company else None
        )
        if duplicate:
            self._merge(duplicate.job, job_data, source)
            return _Processed(duplicate.job, created=False, duplicate_method=duplicate.method)

        recruiter = self._recruiter(job_data, source, company)
        job = Job(
            external_id=job_data.external_id,
            source_id=source.id,
            title=job_data.title,
            normalized_title=job_data.normalized_title,
            description=job_data.description,
            company=company,
            recruiter=recruiter,
            location=job_data.location_raw,
            city=job_data.city,
            country=job_data.country,
            is_remote=job_data.is_remote,
            is_hybrid=job_data.is_hybrid,
            contract_type=job_data.contract_type,
            work_time=job_data.work_time,
            salary_min=job_data.salary_min,
            salary_max=job_data.salary_max,
            salary_currency=job_data.salary_currency,
            salary_period=job_data.salary_period,
            salary_raw=job_data.salary_raw,
            experience_level=job_data.experience_level,
            min_years_experience=job_data.min_years_experience,
            languages=job_data.languages,
            application_url=job_data.application_url,
            application_email=job_data.application_email,
            source_url=job_data.source_url,
            fingerprint=job_data.fingerprint,
            # UML 17 : une offre validée et complète est ACTIVE, une offre incomplète reste NEW.
            status=JobStatus.ACTIVE if outcome.is_complete else JobStatus.NEW,
            quality_issues=outcome.quality_issues,
            published_at=job_data.published_at,
            expires_at=job_data.expires_at,
            scraped_at=utcnow(),
            last_checked_at=utcnow(),
            raw_data=job_data.raw_data,
            normalized_data=job_data.model_dump(mode="json", exclude={"raw_data"}),
            created_by_id=created_by_id,
        )
        job.skills = self._job_skills(job_data)
        job.sources = [
            JobSource(
                source_id=source.id, external_id=job_data.external_id, url=job_data.source_url
            )
        ]
        self.session.add(job)
        self.session.flush()
        return _Processed(job, created=True)

    def _merge(self, job: Job, job_data: NormalizedJob, source: Source) -> None:
        """Offre déjà connue : on garde l'existant et on complète les champs vides."""
        now = utcnow()
        job.last_checked_at = now
        if job.status == JobStatus.EXPIRED and not (
            job_data.expires_at and job_data.expires_at < now
        ):
            job.status = JobStatus.ACTIVE  # l'offre est de nouveau publiée
        for field_name in (
            "description", "city", "country", "contract_type", "work_time", "salary_min",
            "salary_max", "salary_currency", "salary_period", "salary_raw", "experience_level",
            "min_years_experience", "application_url", "application_email", "published_at",
            "expires_at",
        ):  # fmt: skip
            value = getattr(job_data, field_name)
            if value is not None and getattr(job, field_name) is None:
                setattr(job, field_name, value)
        known_skills = {normalize_text(item.skill.name) for item in job.skills}
        for job_skill in self._job_skills(job_data):
            if normalize_text(job_skill.skill.name) not in known_skills:
                job.skills.append(job_skill)

        link = next(
            (
                item
                for item in job.sources
                if item.source_id == source.id
                and (item.external_id == job_data.external_id or not job_data.external_id)
            ),
            None,
        )
        if link:
            link.last_seen_at = now
            link.url = link.url or job_data.source_url
        else:
            job.sources.append(
                JobSource(
                    source_id=source.id, external_id=job_data.external_id, url=job_data.source_url
                )
            )
        self.session.flush()

    def _company(
        self, job_data: NormalizedJob, source: Source, origin: DataOrigin
    ) -> Company | None:
        if not job_data.company_name:
            return None
        return self.companies.find_or_create_from_collect(
            job_data.company_name,
            job_data.company,
            origin=origin,
            source_id=source.id,
            source_url=job_data.source_url,
        )

    def _recruiter(
        self, job_data: NormalizedJob, source: Source, company: Company | None
    ) -> Recruiter | None:
        if not job_data.recruiter:
            return None
        return self.recruiters.find_or_create_from_collect(
            job_data.recruiter,
            company_id=company.id if company else None,
            source_id=source.id,
            default_source_url=job_data.source_url,
        )

    def _job_skills(self, job_data: NormalizedJob) -> list[JobSkill]:
        return [
            JobSkill(skill=self.catalog.get_or_create(item.name), requirement=item.requirement)
            for item in job_data.skills
        ]

    # --- NOTIFY ---

    def _notify(self, high_matches: dict[object, list[ScoredJob]], created_jobs: list[Job]) -> None:
        notifications = NotificationService(self.session)
        created_ids = {job.id for job in created_jobs}
        for user_id, scored_jobs in high_matches.items():
            fresh = [item for item in scored_jobs if item.job.id in created_ids]
            for item in sorted(fresh, key=lambda scored: -scored.result.score)[
                :MAX_HIGH_MATCH_NOTIFICATIONS
            ]:
                job = item.job
                notifications.notify(
                    user_id,  # type: ignore[arg-type]
                    NotificationType.HIGH_MATCH,
                    f"Offre compatible à {item.result.score}% : {job.title}"[:255],
                    f"{job.title} — {job.company.name if job.company else 'Entreprise non précisée'}",
                    data=_job_notification_data(job, item),
                )

        if not created_jobs:
            return
        count = len(created_jobs)
        for user in UserRepository(self.session).list_active():
            notifications.notify(
                user.id,
                NotificationType.NEW_JOB,
                f"{count} nouvelle(s) offre(s)",
                ", ".join(job.title for job in created_jobs[:5]) + (" …" if count > 5 else ""),
                data={"count": count, "job_ids": [str(job.id) for job in created_jobs[:50]]},
            )
        publish_event(
            EventType.NEW_JOB,
            {"count": count, "job_ids": [str(job.id) for job in created_jobs[:50]]},
        )

    @staticmethod
    def _keep_error(result: IngestionResult, message: str) -> None:
        if len(result.errors) < MAX_ERRORS_KEPT:
            result.errors.append(message)


def _job_notification_data(job: Job, scored: ScoredJob) -> dict[str, object]:
    location = "Télétravail" if job.is_remote else ", ".join(filter(None, [job.city, job.country]))
    return {
        "job_id": str(job.id),
        "job_title": job.title,
        "company_name": job.company.name if job.company else None,
        "location": location or None,
        "score": scored.result.score,
        "matched_skills": scored.result.matched_skills,
        "url": job.source_url or job.application_url,
    }
