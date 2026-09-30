"""Envoi de messages Telegram via l'API Bot officielle.

Configuration (.env) : TELEGRAM_BOT_TOKEN et TELEGRAM_CHAT_ID.
1. Créez un bot avec @BotFather → vous obtenez le token.
2. Envoyez un message à votre bot, puis ouvrez
   https://api.telegram.org/bot<TOKEN>/getUpdates pour lire votre chat_id.

Le token fait partie de l'URL appelée : il ne doit JAMAIS être loggé
(le logger httpx est réduit au niveau WARNING dans core/logging.py).
"""

import html
import logging
from typing import Any

import httpx

from app.core.config import get_settings
from app.core.exceptions import ExternalServiceError
from app.shared.enums import NotificationType

logger = logging.getLogger("app.notifications")

TELEGRAM_API_URL = "https://api.telegram.org"
MAX_MESSAGE_LENGTH = 4000  # limite Telegram : 4096 caractères


def _escape(value: Any) -> str:
    return html.escape(str(value)) if value is not None else "—"


class TelegramService:
    """Envoie des notifications formatées sur Telegram."""

    def __init__(self, client: httpx.Client | None = None) -> None:
        self.settings = get_settings()
        self._client = client

    @property
    def is_configured(self) -> bool:
        return self.settings.TELEGRAM_BOT_TOKEN is not None

    def send_message(self, chat_id: str, text: str) -> None:
        """Envoie un message HTML. Lève ExternalServiceError en cas d'échec."""
        if self.settings.TELEGRAM_BOT_TOKEN is None:
            raise ExternalServiceError("Telegram is not configured", code="TELEGRAM_NOT_CONFIGURED")
        token = self.settings.TELEGRAM_BOT_TOKEN.get_secret_value()
        url = f"{TELEGRAM_API_URL}/bot{token}/sendMessage"
        payload = {
            "chat_id": chat_id,
            "text": text[:MAX_MESSAGE_LENGTH],
            "parse_mode": "HTML",
            "disable_web_page_preview": True,
        }
        try:
            if self._client is not None:
                response = self._client.post(url, json=payload)
            else:
                with httpx.Client(timeout=15) as client:
                    response = client.post(url, json=payload)
        except httpx.HTTPError as exc:
            # str(exc) peut contenir l'URL (donc le token) : on ne log que le type d'erreur.
            logger.error("Telegram request failed: %s", type(exc).__name__)
            raise ExternalServiceError("Telegram request failed", code="TELEGRAM_ERROR") from None
        if response.status_code != 200:
            logger.error("Telegram API error", extra={"status_code": response.status_code})
            raise ExternalServiceError("Telegram API returned an error", code="TELEGRAM_ERROR")

    # --- Messages métier ---

    def send_new_job(self, chat_id: str, data: dict[str, Any]) -> None:
        self.send_message(chat_id, format_job_message("🆕 Nouvelle offre", data))

    def send_high_match(self, chat_id: str, data: dict[str, Any]) -> None:
        self.send_message(chat_id, format_job_message("🔥 Offre très compatible", data))

    def send_application_ready(self, chat_id: str, data: dict[str, Any]) -> None:
        text = (
            "📝 <b>Candidature prête</b>\n"
            f"{_escape(data.get('job_title'))} — {_escape(data.get('company_name'))}\n"
            "Validez l'envoi depuis l'application."
        )
        self.send_message(chat_id, text)

    def send_recruiter_response(self, chat_id: str, data: dict[str, Any]) -> None:
        text = (
            "📬 <b>Réponse d'un recruteur</b>\n"
            f"De : {_escape(data.get('sender_email'))}\n"
            f"Objet : {_escape(data.get('subject'))}\n"
            f"Type détecté : {_escape(data.get('response_type'))}"
        )
        self.send_message(chat_id, text)

    def send_system_error(self, chat_id: str, title: str, message: str) -> None:
        self.send_message(chat_id, f"⚠️ <b>{_escape(title)}</b>\n{_escape(message)}")

    def send_notification(
        self, chat_id: str, notification_type: NotificationType, title: str, message: str,
        data: dict[str, Any],
    ) -> None:  # fmt: skip
        """Choisit le bon format selon le type de notification."""
        match notification_type:
            case NotificationType.NEW_JOB if data.get("job_id"):
                self.send_new_job(chat_id, data)
            case NotificationType.HIGH_MATCH:
                self.send_high_match(chat_id, data)
            case NotificationType.APPLICATION_STATUS if data.get("status") == "ready":
                self.send_application_ready(chat_id, data)
            case NotificationType.RECRUITER_RESPONSE:
                self.send_recruiter_response(chat_id, data)
            case NotificationType.SCRAPING_ERROR | NotificationType.MONITORING:
                self.send_system_error(chat_id, title, message)
            case _:
                self.send_message(chat_id, f"<b>{_escape(title)}</b>\n{_escape(message)}")


def format_job_message(header: str, data: dict[str, Any]) -> str:
    lines = [f"<b>{header}</b>", f"<b>{_escape(data.get('job_title'))}</b>"]
    if data.get("company_name"):
        lines.append(f"🏢 {_escape(data['company_name'])}")
    if data.get("location"):
        lines.append(f"📍 {_escape(data['location'])}")
    if data.get("score") is not None:
        lines.append(f"🎯 Score : {_escape(data['score'])}/100")
    if data.get("matched_skills"):
        lines.append(f"✅ {_escape(', '.join(data['matched_skills'][:8]))}")
    if data.get("url"):
        lines.append(f'<a href="{html.escape(str(data["url"]), quote=True)}">Voir l\'offre</a>')
    return "\n".join(lines)
