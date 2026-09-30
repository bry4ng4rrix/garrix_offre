"""Gestion des connexions WebSocket ouvertes.

Le `WebSocketManager` :
1. garde la liste des WebSockets ouverts, par utilisateur ;
2. écoute le canal Redis des événements (tâche de fond lancée au démarrage de l'API) ;
3. transmet chaque événement au bon utilisateur (ou à tous si `user_id` est vide).
"""

import asyncio
import json
import logging
from collections import defaultdict
from typing import Any

import redis.asyncio as aioredis
from fastapi import WebSocket
from redis.exceptions import RedisError

from app.modules.realtime.events import EVENTS_CHANNEL

logger = logging.getLogger("app.realtime")

RECONNECT_DELAY_SECONDS = 3


class WebSocketManager:
    """Registre des connexions WebSocket et diffusion des événements temps réel."""

    def __init__(self) -> None:
        self._connections: dict[str, set[WebSocket]] = defaultdict(set)

    @property
    def connection_count(self) -> int:
        return sum(len(sockets) for sockets in self._connections.values())

    def register(self, user_id: str, websocket: WebSocket) -> None:
        self._connections[user_id].add(websocket)
        logger.info("WebSocket connected", extra={"user_id": user_id})

    def unregister(self, user_id: str, websocket: WebSocket) -> None:
        sockets = self._connections.get(user_id)
        if sockets is None:
            return
        sockets.discard(websocket)
        if not sockets:
            del self._connections[user_id]
        logger.info("WebSocket disconnected", extra={"user_id": user_id})

    async def send_to_user(self, user_id: str, message: dict[str, Any]) -> None:
        for websocket in list(self._connections.get(user_id, ())):
            await self._safe_send(user_id, websocket, message)

    async def broadcast(self, message: dict[str, Any]) -> None:
        for user_id, sockets in list(self._connections.items()):
            for websocket in list(sockets):
                await self._safe_send(user_id, websocket, message)

    async def dispatch(self, raw_message: str) -> None:
        """Transmet un message venant de Redis aux connexions concernées."""
        try:
            event = json.loads(raw_message)
        except json.JSONDecodeError:
            logger.warning("Invalid realtime event ignored")
            return
        user_id = event.pop("user_id", None)
        if user_id:
            await self.send_to_user(user_id, event)
        else:
            await self.broadcast(event)

    async def listen(self, redis: aioredis.Redis) -> None:
        """Boucle infinie : écoute Redis et relaie les événements (relance après une erreur)."""
        while True:
            try:
                async with redis.pubsub() as pubsub:
                    await pubsub.subscribe(EVENTS_CHANNEL)
                    logger.info("Listening to realtime events")
                    async for message in pubsub.listen():
                        if message.get("type") == "message":
                            await self.dispatch(message["data"])
            except asyncio.CancelledError:
                raise
            except (RedisError, OSError) as exc:
                logger.warning("Realtime listener disconnected from Redis: %s", exc)
                await asyncio.sleep(RECONNECT_DELAY_SECONDS)

    async def _safe_send(self, user_id: str, websocket: WebSocket, message: dict[str, Any]) -> None:
        try:
            await websocket.send_json(message)
        except Exception:  # noqa: BLE001 - connexion fermée côté client
            self.unregister(user_id, websocket)
