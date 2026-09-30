"""Rate limiting simple par IP, basé sur Redis (fenêtre fixe d'une minute).

Principe : pour chaque IP et chaque minute, on incrémente un compteur Redis.
Au-delà de la limite, la requête est refusée avec une erreur 429.

Si Redis est indisponible, on laisse passer la requête (fail-open) et on log
un avertissement : une panne Redis ne doit pas rendre toute l'API inaccessible.
"""

import logging
import time

import redis.asyncio as aioredis
from fastapi import Request
from redis.exceptions import RedisError

from app.core.config import get_settings
from app.core.exceptions import RateLimitError

logger = logging.getLogger("app.security")

WINDOW_SECONDS = 60


async def is_allowed(redis: aioredis.Redis, key: str, limit: int) -> bool:
    """Incrémente le compteur `key` pour la minute courante et vérifie la limite."""
    window = int(time.time() // WINDOW_SECONDS)
    redis_key = f"ratelimit:{key}:{window}"
    try:
        async with redis.pipeline(transaction=True) as pipe:
            pipe.incr(redis_key)
            pipe.expire(redis_key, WINDOW_SECONDS)
            count, _ = await pipe.execute()
    except (RedisError, OSError) as exc:
        logger.warning("Rate limiter unavailable, request allowed: %s", exc)
        return True
    return int(count) <= limit


def client_ip(request: Request) -> str:
    # Derrière nginx, uvicorn (--proxy-headers) remplace déjà request.client par la vraie IP.
    return request.client.host if request.client else "unknown"


async def auth_rate_limit(request: Request) -> None:
    """Dépendance FastAPI : limite stricte pour login / register / refresh (anti brute-force)."""
    settings = get_settings()
    if not settings.RATE_LIMIT_ENABLED:
        return
    redis: aioredis.Redis = request.app.state.redis
    key = f"auth:{request.url.path}:{client_ip(request)}"
    if not await is_allowed(redis, key, settings.AUTH_RATE_LIMIT_PER_MINUTE):
        logger.warning("Auth rate limit exceeded", extra={"path": request.url.path})
        raise RateLimitError("Too many authentication attempts, please retry in a minute")
