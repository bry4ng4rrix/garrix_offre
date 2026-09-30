"""Appels sortants FastAPI → n8n.

Utilisé quand NOTIFICATION_DELIVERY_MODE=n8n : FastAPI transmet la notification
au workflow n8n "notification" (qui l'envoie ensuite sur Telegram / Email).
Le secret partagé est envoyé dans l'en-tête X-N8N-Webhook-Secret, comme pour les
appels entrants, afin que le workflow puisse vérifier l'origine de l'appel.
"""

import logging
from typing import Any

import httpx

from app.core.config import get_settings
from app.core.exceptions import ExternalServiceError

logger = logging.getLogger("app.n8n")


class N8nClient:
    """Client HTTP minimal vers les webhooks n8n."""

    def __init__(self, client: httpx.Client | None = None) -> None:
        self.settings = get_settings()
        self._client = client

    def post_webhook(self, url: str, payload: dict[str, Any]) -> None:
        headers = {"X-N8N-Webhook-Secret": self.settings.N8N_WEBHOOK_SECRET.get_secret_value()}
        try:
            if self._client is not None:
                response = self._client.post(url, json=payload, headers=headers)
            else:
                with httpx.Client(timeout=15) as client:
                    response = client.post(url, json=payload, headers=headers)
        except httpx.HTTPError as exc:
            logger.error("n8n webhook call failed: %s", type(exc).__name__)
            raise ExternalServiceError("n8n is unreachable", code="N8N_UNREACHABLE") from None
        if response.status_code >= 400:
            logger.error("n8n webhook error", extra={"status_code": response.status_code})
            raise ExternalServiceError("n8n webhook returned an error", code="N8N_ERROR")

    def send_notification(self, payload: dict[str, Any]) -> None:
        url = self.settings.N8N_NOTIFICATION_WEBHOOK_URL
        if not url:
            raise ExternalServiceError(
                "N8N_NOTIFICATION_WEBHOOK_URL is not configured", code="N8N_NOT_CONFIGURED"
            )
        self.post_webhook(url, payload)

    def is_healthy(self) -> bool:
        try:
            with httpx.Client(timeout=3) as client:
                response = client.get(f"{self.settings.N8N_BASE_URL.rstrip('/')}/healthz")
            return response.status_code == 200
        except httpx.HTTPError:
            return False
