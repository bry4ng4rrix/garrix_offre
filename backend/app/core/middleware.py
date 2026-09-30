"""Middlewares HTTP de l'application.

Ils sont écrits en "ASGI pur" (classe avec `__call__(scope, receive, send)`) :
c'est un peu plus verbeux qu'un décorateur, mais cela permet de contrôler le body
reçu morceau par morceau (indispensable pour limiter la taille des uploads).

Ordre d'exécution (du plus externe au plus interne) :
1. RequestLoggingMiddleware : identifiant de requête + log de chaque requête
2. RateLimitMiddleware      : limite globale de requêtes par IP
3. BodySizeLimitMiddleware  : refuse les bodies trop gros (413)
"""

import logging
import re
import time
import uuid

from fastapi import HTTPException, status
from fastapi.responses import JSONResponse
from starlette.datastructures import Headers, MutableHeaders
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.config import get_settings
from app.core.exceptions import error_body
from app.core.rate_limit import is_allowed

request_logger = logging.getLogger("app.request")

_REQUEST_ID_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
QUIET_PATHS = {"/health", "/ready"}


class RequestLoggingMiddleware:
    """Ajoute un en-tête X-Request-ID et écrit un log par requête (sans query string)."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        incoming_id = Headers(scope=scope).get("x-request-id", "")
        request_id = incoming_id if _REQUEST_ID_PATTERN.match(incoming_id) else uuid.uuid4().hex
        state = scope.setdefault("state", {})
        state["request_id"] = request_id

        status_code = 500
        started = time.perf_counter()

        async def send_with_request_id(message: Message) -> None:
            nonlocal status_code
            if message["type"] == "http.response.start":
                status_code = message["status"]
                MutableHeaders(scope=message).append("X-Request-ID", request_id)
            await send(message)

        try:
            await self.app(scope, receive, send_with_request_id)
        finally:
            path = scope.get("path", "")
            level = logging.DEBUG if path in QUIET_PATHS else logging.INFO
            if status_code >= 500:
                level = logging.ERROR
            client = scope.get("client")
            request_logger.log(
                level,
                "%s %s -> %s",
                scope.get("method"),
                path,
                status_code,
                extra={
                    "request_id": request_id,
                    "status_code": status_code,
                    "duration_ms": round((time.perf_counter() - started) * 1000, 1),
                    "client_ip": client[0] if client else None,
                    "user_id": state.get("user_id"),
                },
            )


class RateLimitMiddleware:
    """Limite globale : RATE_LIMIT_PER_MINUTE requêtes par minute et par IP."""

    # Chemins non limités : sondes de santé, documentation, webhooks n8n (protégés par secret).
    EXEMPT_PREFIXES = ("/health", "/ready", "/docs", "/redoc", "/openapi.json", "/api/v1/webhooks/")

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        settings = get_settings()
        path: str = scope.get("path", "")
        if (
            scope["type"] != "http"
            or not settings.RATE_LIMIT_ENABLED
            or path.startswith(self.EXEMPT_PREFIXES)
        ):
            await self.app(scope, receive, send)
            return

        client = scope.get("client")
        ip = client[0] if client else "unknown"
        redis = scope["app"].state.redis
        if not await is_allowed(redis, f"global:{ip}", settings.RATE_LIMIT_PER_MINUTE):
            response = JSONResponse(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                content=error_body("RATE_LIMITED", "Too many requests, please retry later"),
                headers={"Retry-After": "60"},
            )
            await response(scope, receive, send)
            return
        await self.app(scope, receive, send)


class BodySizeLimitMiddleware:
    """Refuse les requêtes dont le body dépasse la limite (JSON ou upload multipart)."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        settings = get_settings()
        headers = Headers(scope=scope)
        is_upload = headers.get("content-type", "").startswith("multipart/form-data")
        # Marge de 1 Mo pour les en-têtes multipart autour du fichier.
        limit = (
            settings.max_upload_size_bytes + 1024 * 1024
            if is_upload
            else settings.max_request_size_bytes
        )

        declared_length = headers.get("content-length")
        if declared_length and declared_length.isdigit() and int(declared_length) > limit:
            response = JSONResponse(
                status_code=status.HTTP_413_CONTENT_TOO_LARGE,
                content=error_body("PAYLOAD_TOO_LARGE", "Request body is too large"),
            )
            await response(scope, receive, send)
            return

        received_bytes = 0

        async def limited_receive() -> Message:
            nonlocal received_bytes
            message = await receive()
            if message["type"] == "http.request":
                received_bytes += len(message.get("body", b""))
                if received_bytes > limit:
                    # FastAPI relaie les HTTPException levées pendant la lecture du body.
                    raise HTTPException(
                        status_code=status.HTTP_413_CONTENT_TOO_LARGE,
                        detail="Request body is too large",
                    )
            return message

        await self.app(scope, limited_receive, send)
