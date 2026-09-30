from app.api.dependencies import DbSession
from app.modules.matching.service import MatchingService


def get_matching_service(session: DbSession) -> MatchingService:
    return MatchingService(session)
