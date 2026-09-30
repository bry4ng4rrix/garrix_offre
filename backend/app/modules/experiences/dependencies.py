from app.api.dependencies import DbSession
from app.modules.experiences.service import (
    ExperienceLevelService,
    ExperiencePreferenceService,
    ExperienceService,
)


def get_experience_service(session: DbSession) -> ExperienceService:
    return ExperienceService(session)


def get_experience_preference_service(session: DbSession) -> ExperiencePreferenceService:
    return ExperiencePreferenceService(session)


def get_experience_level_service(session: DbSession) -> ExperienceLevelService:
    return ExperienceLevelService(session)
