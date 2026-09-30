"""Dépendances FastAPI communes à tous les modules.

Utilisation dans un router :

    @router.get("/me")
    def read_me(user: CurrentUser, db: DbSession): ...

    @router.delete("/{id}")
    def delete_source(admin: SuperUser, db: DbSession): ...
"""

import uuid
from typing import Annotated, Any

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.exceptions import AuthenticationError, PermissionDeniedError
from app.core.security import decode_access_token
from app.modules.auth.token_denylist import is_access_token_revoked
from app.modules.users.models import User
from app.modules.users.repository import UserRepository

bearer_scheme = HTTPBearer(auto_error=False, description="Access token JWT (POST /auth/login)")

DbSession = Annotated[Session, Depends(get_db)]


def authenticate_token(token: str, session: Session) -> tuple[User, dict[str, Any]]:
    """Valide un access token et retourne (utilisateur, payload). Utilisé aussi par le WebSocket."""
    payload = decode_access_token(token)
    if is_access_token_revoked(payload["jti"]):
        raise AuthenticationError("Token has been revoked", code="TOKEN_REVOKED")
    try:
        user_id = uuid.UUID(payload["sub"])
    except ValueError as exc:
        raise AuthenticationError("Invalid access token", code="INVALID_TOKEN") from exc
    user = UserRepository(session).get(user_id)
    if user is None or not user.is_active:
        raise AuthenticationError("User not found or disabled", code="INVALID_TOKEN")
    return user, payload


def get_token_payload(
    request: Request,
    session: DbSession,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> dict[str, Any]:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise AuthenticationError()
    user, payload = authenticate_token(credentials.credentials, session)
    request.state.user = user
    request.state.user_id = str(user.id)  # repris dans les logs de requête
    return payload


def get_current_user(
    request: Request, _payload: Annotated[dict[str, Any], Depends(get_token_payload)]
) -> User:
    user: User = request.state.user
    return user


def get_current_superuser(user: Annotated[User, Depends(get_current_user)]) -> User:
    if not user.is_superuser:
        raise PermissionDeniedError("Administrator rights required", code="ADMIN_REQUIRED")
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]
SuperUser = Annotated[User, Depends(get_current_superuser)]
TokenPayload = Annotated[dict[str, Any], Depends(get_token_payload)]
