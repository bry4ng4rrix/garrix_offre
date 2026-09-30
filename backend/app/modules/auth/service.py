import logging
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.exceptions import AuthenticationError, PermissionDeniedError
from app.core.security import (
    create_access_token,
    generate_refresh_token,
    hash_password,
    hash_token,
    password_needs_rehash,
    verify_password,
)
from app.modules.audit.service import AuditService
from app.modules.auth.models import RefreshToken
from app.modules.auth.repository import RefreshTokenRepository
from app.modules.auth.schemas import TokenPair
from app.modules.auth.token_denylist import revoke_access_token
from app.modules.users.models import User
from app.modules.users.repository import UserRepository
from app.modules.users.service import UserService
from app.shared.enums import ActorType
from app.shared.utils import utcnow

logger = logging.getLogger("app.auth")

# Hash factice : on vérifie quand même un mot de passe quand l'email est inconnu,
# pour que le temps de réponse ne révèle pas si un compte existe.
_DUMMY_HASH = hash_password("dummy-password-for-timing-protection-0")


class AuthService:
    """Inscription, connexion, rotation des refresh tokens et déconnexion."""

    def __init__(self, session: Session) -> None:
        self.session = session
        self.users = UserRepository(session)
        self.refresh_tokens = RefreshTokenRepository(session)
        self.audit = AuditService(session)

    def register(self, email: str, password: str) -> User:
        settings = get_settings()
        # La première inscription est toujours autorisée (création de l'administrateur).
        if not settings.ALLOW_REGISTRATION and self.users.count() > 0:
            raise PermissionDeniedError("Registration is disabled", code="REGISTRATION_DISABLED")
        user = UserService(self.session).create_user(email, password)
        self.audit.record(
            "auth.register", actor_type=ActorType.USER, actor_id=user.id, entity_type="user",
            entity_id=user.id,
        )  # fmt: skip
        self.session.commit()
        return user

    def login(self, email: str, password: str, user_agent: str | None = None) -> TokenPair:
        user = self.users.get_by_email(email)
        if user is None:
            verify_password(password, _DUMMY_HASH)
            logger.warning("Login failed: unknown email")
            raise AuthenticationError("Invalid email or password", code="INVALID_CREDENTIALS")
        if not verify_password(password, user.hashed_password):
            self.audit.record(
                "auth.login_failed", actor_type=ActorType.USER, actor_id=user.id,
                entity_type="user", entity_id=user.id,
            )  # fmt: skip
            self.session.commit()
            raise AuthenticationError("Invalid email or password", code="INVALID_CREDENTIALS")
        if not user.is_active:
            raise AuthenticationError("This account is disabled", code="ACCOUNT_DISABLED")

        if password_needs_rehash(user.hashed_password):
            user.hashed_password = hash_password(password)
        user.last_login_at = utcnow()
        tokens = self._issue_tokens(user, user_agent)
        self.audit.record(
            "auth.login", actor_type=ActorType.USER, actor_id=user.id, entity_type="user",
            entity_id=user.id,
        )  # fmt: skip
        self.session.commit()
        return tokens

    def refresh(self, raw_refresh_token: str, user_agent: str | None = None) -> TokenPair:
        """Rotation : l'ancien refresh token est révoqué, un nouveau couple est émis."""
        stored = self.refresh_tokens.get_by_hash(hash_token(raw_refresh_token))
        if stored is None or stored.expires_at <= utcnow():
            raise AuthenticationError(
                "Invalid or expired refresh token", code="INVALID_REFRESH_TOKEN"
            )
        if stored.revoked_at is not None:
            # Réutilisation d'un token déjà utilisé : possible vol → on coupe toutes les sessions.
            self.refresh_tokens.revoke_all_for_user(stored.user_id)
            self.session.commit()
            logger.warning("Refresh token reuse detected", extra={"user_id": str(stored.user_id)})
            raise AuthenticationError("Refresh token already used", code="INVALID_REFRESH_TOKEN")

        user = self.users.get(stored.user_id)
        if user is None or not user.is_active:
            raise AuthenticationError("Invalid refresh token", code="INVALID_REFRESH_TOKEN")

        stored.revoked_at = utcnow()
        tokens = self._issue_tokens(user, user_agent)
        self.session.commit()
        return tokens

    def logout(
        self,
        user: User,
        access_payload: dict[str, Any],
        raw_refresh_token: str | None,
        all_devices: bool,
    ) -> None:
        revoke_access_token(access_payload["jti"], _expiry_from_payload(access_payload))
        if all_devices:
            self.refresh_tokens.revoke_all_for_user(user.id)
        elif raw_refresh_token:
            stored = self.refresh_tokens.get_by_hash(hash_token(raw_refresh_token))
            if stored and stored.user_id == user.id and stored.revoked_at is None:
                stored.revoked_at = utcnow()
        self.audit.record(
            "auth.logout", actor_type=ActorType.USER, actor_id=user.id, entity_type="user",
            entity_id=user.id, details={"all_devices": all_devices},
        )  # fmt: skip
        self.session.commit()

    def _issue_tokens(self, user: User, user_agent: str | None) -> TokenPair:
        settings = get_settings()
        access = create_access_token(user.id)
        raw_refresh = generate_refresh_token()
        self.refresh_tokens.add(
            RefreshToken(
                user_id=user.id,
                token_hash=hash_token(raw_refresh),
                expires_at=utcnow() + timedelta(days=settings.JWT_REFRESH_TOKEN_EXPIRE_DAYS),
                user_agent=(user_agent or "")[:255] or None,
            )
        )
        return TokenPair(
            access_token=access.token,
            refresh_token=raw_refresh,
            expires_in=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES * 60,
        )


def _expiry_from_payload(payload: dict[str, Any]) -> datetime:
    return datetime.fromtimestamp(int(payload["exp"]), tz=UTC)
