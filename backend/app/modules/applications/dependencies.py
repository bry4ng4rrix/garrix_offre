from app.api.dependencies import DbSession
from app.modules.applications.responses import RecruiterResponseService
from app.modules.applications.service import ApplicationService


def get_application_service(session: DbSession) -> ApplicationService:
    return ApplicationService(session)


def get_response_service(session: DbSession) -> RecruiterResponseService:
    return RecruiterResponseService(session)
