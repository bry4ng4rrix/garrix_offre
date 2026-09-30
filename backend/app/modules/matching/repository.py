import uuid
from dataclasses import asdict
from typing import Any

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert

from app.modules.matching.models import JobMatch, MatchingSettings
from app.modules.matching.scoring import MatchResult
from app.shared.repository import BaseRepository
from app.shared.utils import utcnow


class MatchingSettingsRepository(BaseRepository[MatchingSettings]):
    model = MatchingSettings

    def get_or_create(self, user_id: uuid.UUID) -> MatchingSettings:
        settings_row = self.session.scalar(
            select(MatchingSettings).where(MatchingSettings.user_id == user_id)
        )
        if settings_row is None:
            settings_row = self.add(MatchingSettings(user_id=user_id))
        return settings_row


class JobMatchRepository(BaseRepository[JobMatch]):
    model = JobMatch

    def get_for_job(self, user_id: uuid.UUID, job_id: uuid.UUID) -> JobMatch | None:
        return self.session.scalar(
            select(JobMatch).where(JobMatch.user_id == user_id, JobMatch.job_id == job_id)
        )

    def get_for_jobs(
        self, user_id: uuid.UUID, job_ids: list[uuid.UUID]
    ) -> dict[uuid.UUID, JobMatch]:
        if not job_ids:
            return {}
        stmt = select(JobMatch).where(JobMatch.user_id == user_id, JobMatch.job_id.in_(job_ids))
        return {match.job_id: match for match in self.session.scalars(stmt)}

    def upsert(self, user_id: uuid.UUID, job_id: uuid.UUID, result: MatchResult) -> None:
        """Insère ou met à jour le résultat (une seule ligne par utilisateur et par offre)."""
        values: dict[str, Any] = asdict(result) | {"computed_at": utcnow()}
        stmt = insert(JobMatch).values(id=uuid.uuid4(), user_id=user_id, job_id=job_id, **values)
        stmt = stmt.on_conflict_do_update(index_elements=["user_id", "job_id"], set_=values)
        self.session.execute(stmt)
