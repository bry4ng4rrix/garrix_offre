from app.api.dependencies import DbSession
from app.modules.users.service import UserService


def get_user_service(session: DbSession) -> UserService:
    return UserService(session)
