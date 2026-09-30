import uuid
from datetime import datetime

from sqlalchemy import Select, func, select

from app.modules.applications.models import (
    TERMINAL_STATUSES,
    Application,
    ApplicationStatusHistory,
    RecruiterResponse,
)
from app.shared.enums import ApplicationStatus
from app.shared.repository import BaseRepository


class ApplicationRepository(BaseRepository[Application]):
    model = Application

    def get_for_user(self, application_id: uuid.UUID, user_id: uuid.UUID) -> Application | None:
        return self.session.scalar(
            select(Application).where(
                Application.id == application_id, Application.user_id == user_id
            )
        )

    def get_active_for_job(self, user_id: uuid.UUID, job_id: uuid.UUID) -> Application | None:
        return self.session.scalar(
            select(Application).where(
                Application.user_id == user_id,
                Application.job_id == job_id,
                Application.status.not_in(TERMINAL_STATUSES),
            )
        )

    def list_query(
        self,
        user_id: uuid.UUID,
        status: ApplicationStatus | None = None,
        job_id: uuid.UUID | None = None,
    ) -> Select[Application]:
        stmt = (
            select(Application)
            .where(Application.user_id == user_id)
            .order_by(Application.updated_at.desc())
        )
        if status:
            stmt = stmt.where(Application.status == status)
        if job_id:
            stmt = stmt.where(Application.job_id == job_id)
        return stmt

    def list_active(self, user_id: uuid.UUID | None = None) -> list[Application]:
        stmt = select(Application).where(Application.status.not_in(TERMINAL_STATUSES))
        if user_id:
            stmt = stmt.where(Application.user_id == user_id)
        return list(self.session.scalars(stmt).unique())

    def follow_ups_due(self, now: datetime) -> list[Application]:
        """Candidatures envoyées, sans réponse, dont la date de relance est passée."""
        stmt = select(Application).where(
            Application.status == ApplicationStatus.SUBMITTED,
            Application.follow_up_at <= now,
            Application.response_received_at.is_(None),
        )
        return list(self.session.scalars(stmt).unique())

    def count_by_status(self, user_id: uuid.UUID) -> dict[str, int]:
        stmt = (
            select(Application.status, func.count())
            .where(Application.user_id == user_id)
            .group_by(Application.status)
        )
        return {str(status): count for status, count in self.session.execute(stmt)}


class ApplicationHistoryRepository(BaseRepository[ApplicationStatusHistory]):
    model = ApplicationStatusHistory

    def list_for_application(self, application_id: uuid.UUID) -> list[ApplicationStatusHistory]:
        stmt = (
            select(ApplicationStatusHistory)
            .where(ApplicationStatusHistory.application_id == application_id)
            .order_by(ApplicationStatusHistory.changed_at, ApplicationStatusHistory.id)
        )
        return list(self.session.scalars(stmt))


class RecruiterResponseRepository(BaseRepository[RecruiterResponse]):
    model = RecruiterResponse

    def get_by_message_id(self, message_id: str) -> RecruiterResponse | None:
        return self.session.scalar(
            select(RecruiterResponse).where(RecruiterResponse.message_id == message_id)
        )

    def get_for_user(self, response_id: uuid.UUID, user_id: uuid.UUID) -> RecruiterResponse | None:
        return self.session.scalar(
            select(RecruiterResponse).where(
                RecruiterResponse.id == response_id, RecruiterResponse.user_id == user_id
            )
        )

    def list_query(
        self, user_id: uuid.UUID, application_id: uuid.UUID | None = None
    ) -> Select[RecruiterResponse]:
        stmt = (
            select(RecruiterResponse)
            .where(RecruiterResponse.user_id == user_id)
            .order_by(RecruiterResponse.received_at.desc())
        )
        if application_id:
            stmt = stmt.where(RecruiterResponse.application_id == application_id)
        return stmt
