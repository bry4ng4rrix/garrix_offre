"""Fonctions de sécurité : hash des mots de passe, JWT, tokens aléatoires.

- Mots de passe : Argon2 (jamais stockés en clair).
- Access token : JWT signé, courte durée, contient l'id utilisateur (`sub`) et un `jti`.
- Refresh token : chaîne aléatoire opaque ; seul son hash SHA-256 est stocké en base.
"""

import hashlib
import secrets
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError

from app.core.config import get_settings
from app.core.exceptions import AuthenticationError

ACCESS_TOKEN_TYPE = "access"  # noqa: S105 - ce n'est pas un secret

_password_hasher = PasswordHasher()


def hash_password(password: str) -> str:
    return _password_hasher.hash(password)


def verify_password(password: str, hashed_password: str) -> bool:
    try:
        return _password_hasher.verify(hashed_password, password)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


def password_needs_rehash(hashed_password: str) -> bool:
    """Vrai si les paramètres Argon2 ont changé depuis le hash (mise à niveau au login)."""
    return _password_hasher.check_needs_rehash(hashed_password)


@dataclass(frozen=True)
class AccessToken:
    token: str
    jti: str
    expires_at: datetime


def create_access_token(user_id: uuid.UUID) -> AccessToken:
    settings = get_settings()
    now = datetime.now(UTC)
    expires_at = now + timedelta(minutes=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES)
    jti = uuid.uuid4().hex
    payload = {
        "sub": str(user_id),
        "type": ACCESS_TOKEN_TYPE,
        "jti": jti,
        "iat": now,
        "exp": expires_at,
    }
    token = jwt.encode(
        payload, settings.JWT_SECRET_KEY.get_secret_value(), algorithm=settings.JWT_ALGORITHM
    )
    return AccessToken(token=token, jti=jti, expires_at=expires_at)


def decode_access_token(token: str) -> dict[str, Any]:
    """Vérifie la signature et l'expiration. Lève AuthenticationError si invalide."""
    settings = get_settings()
    try:
        payload: dict[str, Any] = jwt.decode(
            token,
            settings.JWT_SECRET_KEY.get_secret_value(),
            algorithms=[settings.JWT_ALGORITHM],
            options={"require": ["sub", "exp", "jti", "type"]},
        )
    except jwt.ExpiredSignatureError as exc:
        raise AuthenticationError("Access token expired", code="TOKEN_EXPIRED") from exc
    except jwt.InvalidTokenError as exc:
        raise AuthenticationError("Invalid access token", code="INVALID_TOKEN") from exc
    if payload.get("type") != ACCESS_TOKEN_TYPE:
        raise AuthenticationError("Invalid token type", code="INVALID_TOKEN")
    return payload


def generate_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def hash_token(token: str) -> str:
    """Hash SHA-256 d'un token : c'est cette valeur qui est stockée en base."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def secrets_are_equal(received: str | None, expected: str) -> bool:
    """Comparaison en temps constant (évite les attaques temporelles)."""
    if not received:
        return False
    return secrets.compare_digest(received.encode("utf-8"), expected.encode("utf-8"))
