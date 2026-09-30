"""Endpoint WebSocket : WS /api/v1/ws

Connexion depuis Flutter :

    ws://localhost:8000/api/v1/ws?token=<access_token>
    (ou en-tête "Authorization: Bearer <access_token>")

- Le serveur envoie `{"type": "connected", ...}` puis les événements temps réel.
- Le client peut envoyer "ping" : le serveur répond `{"type": "pong"}`.
- La connexion est fermée (code 4001) quand l'access token expire : le client doit se
  reconnecter avec un token rafraîchi, puis relire les notifications non lues via REST (RG-15).
"""

import asyncio
import contextlib
import logging
import uuid
from typing import Any

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, status
from starlette.concurrency import run_in_threadpool

from app.api.dependencies import authenticate_token
from app.core.database import session_scope
from app.core.exceptions import AuthenticationError
from app.modules.notifications.repository import NotificationRepository
from app.modules.realtime.manager import WebSocketManager
from app.shared.utils import utcnow

router = APIRouter(tags=["Realtime"])
logger = logging.getLogger("app.realtime")

TOKEN_EXPIRED_CLOSE_CODE = 4001


def _extract_token(websocket: WebSocket) -> str | None:
    token = websocket.query_params.get("token")
    if token:
        return token
    authorization = websocket.headers.get("authorization", "")
    if authorization.lower().startswith("bearer "):
        return authorization[7:].strip()
    return None


def _authenticate(token: str) -> tuple[uuid.UUID, dict[str, Any], int]:
    with session_scope() as session:
        user, payload = authenticate_token(token, session)
        unread = NotificationRepository(session).count_unread(user.id)
        return user.id, payload, unread


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket) -> None:
    token = _extract_token(websocket)
    if not token:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Missing token")
        return
    try:
        user_id, payload, unread = await run_in_threadpool(_authenticate, token)
    except AuthenticationError as exc:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason=exc.code)
        return

    manager: WebSocketManager = websocket.app.state.ws_manager
    user_key = str(user_id)
    await websocket.accept()
    manager.register(user_key, websocket)

    async def close_when_token_expires() -> None:
        await asyncio.sleep(max(0, int(payload["exp"]) - int(utcnow().timestamp())))
        with contextlib.suppress(Exception):
            await websocket.close(code=TOKEN_EXPIRED_CLOSE_CODE, reason="Token expired")

    expiry_task = asyncio.create_task(close_when_token_expires())
    try:
        await websocket.send_json(
            {"type": "connected", "data": {"user_id": user_key, "unread_notifications": unread}}
        )
        while True:
            incoming = await websocket.receive_text()
            if incoming.strip().lower() in {"ping", '{"type":"ping"}', '{"type": "ping"}'}:
                await websocket.send_json({"type": "pong"})
    except WebSocketDisconnect:
        pass
    except RuntimeError:
        # La connexion a été fermée par le serveur (ex: expiration du token).
        pass
    finally:
        expiry_task.cancel()
        manager.unregister(user_key, websocket)
