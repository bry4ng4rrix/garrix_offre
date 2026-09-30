import uuid

from sqlalchemy import select

from app.modules.job_titles.models import JobTitle
from app.shared.repository import BaseRepository


class JobTitleRepository(BaseRepository[JobTitle]):
    model = JobTitle

    def list_for_user(self, user_id: uuid.UUID, enabled_only: bool = False) -> list[JobTitle]:
        stmt = select(JobTitle).where(JobTitle.user_id == user_id).order_by(JobTitle.title)
        if enabled_only:
            stmt = stmt.where(JobTitle.enabled.is_(True))
        return list(self.session.scalars(stmt))

    def get_for_user(self, job_title_id: uuid.UUID, user_id: uuid.UUID) -> JobTitle | None:
        return self.session.scalar(
            select(JobTitle).where(JobTitle.id == job_title_id, JobTitle.user_id == user_id)
        )

    def get_by_normalized(self, user_id: uuid.UUID, normalized_title: str) -> JobTitle | None:
        return self.session.scalar(
            select(JobTitle).where(
                JobTitle.user_id == user_id, JobTitle.normalized_title == normalized_title
            )
        )
