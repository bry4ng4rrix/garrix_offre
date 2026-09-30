"""Liste des access tokens révoqués (après un logout).

Un JWT reste valide jusqu'à son expiration. Pour qu'un logout soit immédiat,
on enregistre son identifiant (`jti`) dans Redis jusqu'à son expiration naturelle.
"""

import logging
from datetime import datetime

from redis.exceptions import RedisError

from app.core.redis import get_redis
from app.shared.utils import utcnow

logger = logging.getLogger("app.auth")

_KEY_PREFIX = "auth:revoked_jti:"


def revoke_access_token(jti: str, expires_at: datetime) -> None:
    ttl_seconds = int((expires_at - utcnow()).total_seconds())
    if ttl_seconds <= 0:
        return
    try:
        get_redis().set(f"{_KEY_PREFIX}{jti}", "1", ex=ttl_seconds)
    except RedisError as exc:
        logger.warning("Could not revoke access token (Redis unavailable): %s", exc)


def is_access_token_revoked(jti: str) -> bool:
    try:
        return bool(get_redis().exists(f"{_KEY_PREFIX}{jti}"))
    except RedisError as exc:
        # Fail-open : les access tokens ont une durée de vie courte.
        logger.warning("Could not check token denylist (Redis unavailable): %s", exc)
        return False
