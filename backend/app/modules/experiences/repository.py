import uuid

from sqlalchemy import select

from app.modules.experiences.models import Experience, ExperienceLevel, ExperiencePreference
from app.modules.skills.models import Skill
from app.shared.repository import BaseRepository


class ExperienceLevelRepository(BaseRepository[ExperienceLevel]):
    model = ExperienceLevel

    def get_by_code(self, code: str) -> ExperienceLevel | None:
        return self.session.scalar(select(ExperienceLevel).where(ExperienceLevel.code == code))

    def list_levels(self) -> list[ExperienceLevel]:
        return list(self.session.scalars(select(ExperienceLevel).order_by(ExperienceLevel.rank)))

    def ranks_by_code(self) -> dict[str, int]:
        return {level.code: level.rank for level in self.list_levels()}


class ExperienceRepository(BaseRepository[Experience]):
    model = Experience

    def list_for_profile(self, profile_id: uuid.UUID) -> list[Experience]:
        stmt = (
            select(Experience)
            .where(Experience.profile_id == profile_id)
            .order_by(Experience.is_current.desc(), Experience.start_date.desc())
        )
        return list(self.session.scalars(stmt))

    def get_for_profile(self, experience_id: uuid.UUID, profile_id: uuid.UUID) -> Experience | None:
        return self.session.scalar(
            select(Experience).where(
                Experience.id == experience_id, Experience.profile_id == profile_id
            )
        )


class ExperiencePreferenceRepository(BaseRepository[ExperiencePreference]):
    model = ExperiencePreference

    def list_for_user(
        self, user_id: uuid.UUID, enabled_only: bool = False
    ) -> list[ExperiencePreference]:
        stmt = (
            select(ExperiencePreference)
            .join(ExperiencePreference.skill)
            .where(ExperiencePreference.user_id == user_id)
            .order_by(Skill.name)
        )
        if enabled_only:
            stmt = stmt.where(ExperiencePreference.enabled.is_(True))
        return list(self.session.scalars(stmt).unique())

    def get_for_user(
        self, preference_id: uuid.UUID, user_id: uuid.UUID
    ) -> ExperiencePreference | None:
        return self.session.scalar(
            select(ExperiencePreference).where(
                ExperiencePreference.id == preference_id, ExperiencePreference.user_id == user_id
            )
        )

    def get_by_skill(self, user_id: uuid.UUID, skill_id: uuid.UUID) -> ExperiencePreference | None:
        return self.session.scalar(
            select(ExperiencePreference).where(
                ExperiencePreference.user_id == user_id, ExperiencePreference.skill_id == skill_id
            )
        )
