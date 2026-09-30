from app.api.dependencies import DbSession
from app.modules.recruiters.service import RecruiterService


def get_recruiter_service(session: DbSession) -> RecruiterService:
    return RecruiterService(session)
