import uuid
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import ColumnElement, Select, and_, exists, func, or_, select, update

from app.modules.applications.models import TERMINAL_STATUSES, Application
from app.modules.companies.models import Company
from app.modules.jobs.models import Job, JobSkill, JobSource, JobUserState
from app.modules.jobs.schemas import JobSortField, JobStatusFilter
from app.modules.matching.models import JobMatch
from app.modules.skills.models import Skill
from app.modules.sources.models import Source
from app.shared.enums import ApplicationStatus, JobStatus, SourceCategory
from app.shared.repository import BaseRepository
from app.shared.utils import normalize_text

VISIBLE_STATUSES = (JobStatus.NEW, JobStatus.ACTIVE)


@dataclass
class JobFilters:
    """Critères de recherche de GET /jobs (tous optionnels)."""

    search: str | None = None
    min_score: int | None = None
    contract_type: str | None = None
    remote: bool | None = None
    location: str | None = None
    skill: str | None = None
    company: str | None = None
    experience_level: str | None = None
    source: str | None = None
    source_category: SourceCategory | None = None
    status: JobStatusFilter | None = None
    published_after: datetime | None = None
    published_before: datetime | None = None
    sort_by: JobSortField = JobSortField.PUBLISHED_AT
    sort_desc: bool = True


def _as_uuid(value: str) -> uuid.UUID | None:
    try:
        return uuid.UUID(value)
    except ValueError:
        return None


class JobRepository(BaseRepository[Job]):
    model = Job

    # --- Recherche ---

    def search_query(self, user_id: uuid.UUID, filters: JobFilters) -> Select[tuple[Job]]:
        stmt = select(Job)
        needs_match = filters.min_score is not None or filters.sort_by == JobSortField.SCORE
        if needs_match:
            stmt = stmt.outerjoin(
                JobMatch, and_(JobMatch.job_id == Job.id, JobMatch.user_id == user_id)
            )
        if filters.min_score is not None:
            stmt = stmt.where(JobMatch.score >= filters.min_score)

        if filters.search:
            pattern = f"%{filters.search}%"
            company_match = exists().where(
                Company.id == Job.company_id, Company.name.ilike(pattern)
            )
            stmt = stmt.where(
                or_(Job.title.ilike(pattern), Job.description.ilike(pattern), company_match)
            )
        if filters.contract_type:
            stmt = stmt.where(Job.contract_type == filters.contract_type.lower())
        if filters.remote is not None:
            stmt = stmt.where(Job.is_remote.is_(filters.remote))
        if filters.location:
            pattern = f"%{filters.location}%"
            stmt = stmt.where(
                or_(
                    Job.city.ilike(pattern), Job.country.ilike(pattern), Job.location.ilike(pattern)
                )
            )
        if filters.skill:
            stmt = stmt.where(
                exists().where(
                    JobSkill.job_id == Job.id,
                    JobSkill.skill_id == Skill.id,
                    Skill.normalized_name == normalize_text(filters.skill),
                )
            )
        if filters.company:
            company_id = _as_uuid(filters.company)
            stmt = stmt.where(
                Job.company_id == company_id
                if company_id
                else exists().where(
                    Company.id == Job.company_id, Company.name.ilike(f"%{filters.company}%")
                )
            )
        if filters.experience_level:
            stmt = stmt.where(Job.experience_level == filters.experience_level.lower())
        if filters.source:
            source_id = _as_uuid(filters.source)
            source_condition = (
                JobSource.source_id == source_id
                if source_id
                else and_(JobSource.source_id == Source.id, Source.name.ilike(filters.source))
            )
            stmt = stmt.where(exists().where(JobSource.job_id == Job.id, source_condition))
        if filters.source_category:
            stmt = stmt.where(
                exists().where(
                    JobSource.job_id == Job.id,
                    JobSource.source_id == Source.id,
                    Source.category == filters.source_category,
                )
            )
        if filters.published_after:
            stmt = stmt.where(Job.published_at >= filters.published_after)
        if filters.published_before:
            stmt = stmt.where(Job.published_at <= filters.published_before)

        stmt = stmt.where(*self._status_conditions(user_id, filters.status))
        return stmt.order_by(*self._ordering(filters, needs_match))

    def _status_conditions(
        self, user_id: uuid.UUID, status: JobStatusFilter | None
    ) -> list[ColumnElement[bool]]:
        def user_state(*conditions: ColumnElement[bool]) -> ColumnElement[bool]:
            return exists().where(
                JobUserState.job_id == Job.id, JobUserState.user_id == user_id, *conditions
            )

        ignored = user_state(JobUserState.is_ignored.is_(True))
        match status:
            case None:
                return [Job.status.in_(VISIBLE_STATUSES), ~ignored]
            case JobStatusFilter.ALL:
                return []
            case JobStatusFilter.UNSEEN:
                return [
                    Job.status.in_(VISIBLE_STATUSES),
                    ~ignored,
                    ~user_state(JobUserState.seen_at.is_not(None)),
                ]
            case JobStatusFilter.SAVED:
                return [user_state(JobUserState.is_saved.is_(True))]
            case JobStatusFilter.IGNORED:
                return [ignored]
            case JobStatusFilter.APPLIED:
                return [
                    exists().where(
                        Application.job_id == Job.id,
                        Application.user_id == user_id,
                        Application.status != ApplicationStatus.NOT_APPLIED,
                    )
                ]
            case _:
                return [Job.status == JobStatus(status.value)]

    @staticmethod
    def _ordering(filters: JobFilters, has_match: bool) -> list[ColumnElement[object]]:
        match filters.sort_by:
            case JobSortField.SCORE if has_match:
                column: ColumnElement[object] = JobMatch.score  # type: ignore[assignment]
            case JobSortField.CREATED_AT:
                column = Job.created_at  # type: ignore[assignment]
            case JobSortField.TITLE:
                column = Job.title  # type: ignore[assignment]
            case _:
                column = func.coalesce(Job.published_at, Job.created_at)
        primary = column.desc().nulls_last() if filters.sort_desc else column.asc().nulls_last()
        return [primary, Job.id]

    # --- Données propres à un utilisateur (chargées en lot pour une page d'offres) ---

    def get_states(
        self, user_id: uuid.UUID, job_ids: list[uuid.UUID]
    ) -> dict[uuid.UUID, JobUserState]:
        if not job_ids:
            return {}
        stmt = select(JobUserState).where(
            JobUserState.user_id == user_id, JobUserState.job_id.in_(job_ids)
        )
        return {state.job_id: state for state in self.session.scalars(stmt)}

    def get_state(self, user_id: uuid.UUID, job_id: uuid.UUID) -> JobUserState | None:
        return self.get_states(user_id, [job_id]).get(job_id)

    def get_active_applications(
        self, user_id: uuid.UUID, job_ids: list[uuid.UUID]
    ) -> dict[uuid.UUID, tuple[uuid.UUID, ApplicationStatus]]:
        if not job_ids:
            return {}
        stmt = select(Application.job_id, Application.id, Application.status).where(
            Application.user_id == user_id,
            Application.job_id.in_(job_ids),
            Application.status.not_in(TERMINAL_STATUSES),
        )
        return {job_id: (app_id, status) for job_id, app_id, status in self.session.execute(stmt)}

    # --- Déduplication ---

    def find_by_source_external_id(self, source_id: uuid.UUID, external_id: str) -> Job | None:
        stmt = (
            select(Job)
            .join(JobSource, JobSource.job_id == Job.id)
            .where(JobSource.source_id == source_id, JobSource.external_id == external_id)
        )
        return self.session.scalars(stmt).unique().first()

    def find_by_url(self, url: str) -> Job | None:
        stmt = (
            select(Job)
            .outerjoin(JobSource, JobSource.job_id == Job.id)
            .where(or_(Job.source_url == url, JobSource.url == url))
        )
        return self.session.scalars(stmt).unique().first()

    def find_by_fingerprint(self, fingerprint: str) -> Job | None:
        return (
            self.session.scalars(select(Job).where(Job.fingerprint == fingerprint)).unique().first()
        )

    def similarity_candidates(self, company_id: uuid.UUID, since: datetime) -> list[Job]:
        stmt = select(Job).where(
            Job.company_id == company_id, func.coalesce(Job.published_at, Job.created_at) >= since
        )
        return list(self.session.scalars(stmt).unique())

    def get_job_source(
        self, job_id: uuid.UUID, source_id: uuid.UUID, external_id: str | None
    ) -> JobSource | None:
        stmt = select(JobSource).where(JobSource.job_id == job_id, JobSource.source_id == source_id)
        if external_id:
            stmt = stmt.where(JobSource.external_id == external_id)
        return self.session.scalars(stmt).first()

    # --- Maintenance ---

    def expire_outdated(self, now: datetime, stale_before: datetime) -> int:
        result = self.session.execute(
            update(Job)
            .where(
                Job.status.in_(VISIBLE_STATUSES),
                or_(
                    Job.expires_at < now,
                    func.coalesce(Job.last_checked_at, Job.created_at) < stale_before,
                ),
            )
            .values(status=JobStatus.EXPIRED)
        )
        return int(getattr(result, "rowcount", 0) or 0)

    def archive_expired(self, expired_before: datetime) -> int:
        result = self.session.execute(
            update(Job)
            .where(Job.status == JobStatus.EXPIRED, Job.updated_at < expired_before)
            .values(status=JobStatus.ARCHIVED)
        )
        return int(getattr(result, "rowcount", 0) or 0)


class JobUserStateRepository(BaseRepository[JobUserState]):
    model = JobUserState

    def get_or_create(self, user_id: uuid.UUID, job_id: uuid.UUID) -> JobUserState:
        state = self.session.scalar(
            select(JobUserState).where(
                JobUserState.user_id == user_id, JobUserState.job_id == job_id
            )
        )
        if state is None:
            state = self.add(JobUserState(user_id=user_id, job_id=job_id))
        return state
