from app.api.dependencies import DbSession
from app.modules.sources.service import SourceService


def get_source_service(session: DbSession) -> SourceService:
    return SourceService(session)
