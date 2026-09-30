from app.api.dependencies import DbSession
from app.modules.auth.service import AuthService


def get_auth_service(session: DbSession) -> AuthService:
    return AuthService(session)
