"""Authentification des webhooks n8n.

n8n envoie le secret partagé dans l'en-tête `X-N8N-Webhook-Secret` (valeur N8N_WEBHOOK_SECRET
du .env, jamais écrite dans le code ni dans les workflows).
"""

import logging
from dataclasses import dataclass
from typing import Annotated

from fastapi import Depends, Header, Request

from app.core.config import get_settings
from app.core.exceptions import AuthenticationError
from app.core.security import secrets_are_equal

logger = logging.getLogger("app.n8n")


def verify_n8n_secret(
    request: Request,
    x_n8n_webhook_secret: Annotated[
        str | None, Header(description="Secret partagé avec n8n")
    ] = None,
) -> None:
    expected = get_settings().N8N_WEBHOOK_SECRET.get_secret_value()
    if not secrets_are_equal(x_n8n_webhook_secret, expected):
        client = request.client.host if request.client else "unknown"
        logger.warning(
            "Invalid n8n webhook secret", extra={"client_ip": client, "path": request.url.path}
        )
        raise AuthenticationError("Invalid webhook secret", code="INVALID_WEBHOOK_SECRET")


@dataclass
class WebhookContext:
    """Métadonnées optionnelles envoyées par n8n dans les en-têtes."""

    idempotency_key: str | None
    workflow_name: str | None
    execution_id: str | None


def webhook_context(
    idempotency_key: Annotated[str | None, Header(max_length=255)] = None,
    x_n8n_workflow: Annotated[str | None, Header(max_length=200)] = None,
    x_n8n_execution_id: Annotated[str | None, Header(max_length=255)] = None,
) -> WebhookContext:
    return WebhookContext(idempotency_key, x_n8n_workflow, x_n8n_execution_id)


N8nContext = Annotated[WebhookContext, Depends(webhook_context)]
