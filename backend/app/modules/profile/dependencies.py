from app.api.dependencies import DbSession
from app.modules.profile.service import ProfileService


def get_profile_service(session: DbSession) -> ProfileService:
    return ProfileService(session)
