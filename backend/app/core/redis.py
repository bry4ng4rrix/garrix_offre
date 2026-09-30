"""Clients Redis.

Redis sert à trois choses dans ce projet :
1. le rate limiting (compteurs par IP) ;
2. la liste des access tokens révoqués (logout) ;
3. le bus d'événements temps réel (pub/sub) entre les services et le WebSocket.
Celery utilise aussi Redis comme broker (base n°1 par défaut).

- `get_redis()` : client synchrone, pour les services et les tâches Celery.
- `create_async_redis()` : client asynchrone, créé au démarrage de l'API (WebSocket, middlewares).
"""

import logging

import redis
import redis.asyncio as aioredis

from app.core.config import get_settings

logger = logging.getLogger("app.redis")

_sync_client: redis.Redis | None = None


def get_redis() -> redis.Redis:
    """Client Redis synchrone partagé (thread-safe grâce à son pool de connexions)."""
    global _sync_client
    if _sync_client is None:
        _sync_client = redis.Redis.from_url(
            get_settings().REDIS_URL,
            decode_responses=True,
            socket_connect_timeout=2,
            socket_timeout=2,
            health_check_interval=30,
        )
    return _sync_client


def create_async_redis() -> aioredis.Redis:
    return aioredis.Redis.from_url(
        get_settings().REDIS_URL,
        decode_responses=True,
        socket_connect_timeout=2,
        health_check_interval=30,
    )


def ping_redis() -> bool:
    try:
        return bool(get_redis().ping())
    except redis.RedisError as exc:
        logger.warning("Redis ping failed: %s", exc)
        return False
