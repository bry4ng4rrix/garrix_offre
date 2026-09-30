from app.api.dependencies import DbSession
from app.modules.job_titles.service import JobTitleService


def get_job_title_service(session: DbSession) -> JobTitleService:
    return JobTitleService(session)
