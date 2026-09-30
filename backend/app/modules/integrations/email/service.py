"""Envoi d'emails via SMTP (bibliothèque standard `smtplib`).

Configuration (.env) : SMTP_HOST, SMTP_PORT, SMTP_USERNAME, SMTP_PASSWORD, SMTP_FROM,
SMTP_USE_TLS (STARTTLS, port 587) ou SMTP_USE_SSL (port 465).

Ce service est synchrone : il est appelé depuis les tâches Celery, jamais directement
pendant une requête HTTP (sauf l'envoi explicite d'une candidature validée).
"""

import logging
import smtplib
import ssl
from dataclasses import dataclass
from email.message import EmailMessage
from email.utils import make_msgid
from typing import Any

from app.core.config import get_settings
from app.core.exceptions import ExternalServiceError
from app.modules.integrations.email import templates
from app.shared.enums import NotificationType

logger = logging.getLogger("app.notifications")


@dataclass(frozen=True)
class EmailAttachment:
    filename: str
    content: bytes
    mime_type: str


class EmailService:
    """Construit et envoie des emails (notifications, candidatures)."""

    def __init__(self) -> None:
        self.settings = get_settings()

    @property
    def is_configured(self) -> bool:
        return self.settings.email_enabled

    def send_email(
        self,
        to: str,
        subject: str,
        text_body: str,
        html_body: str | None = None,
        attachments: list[EmailAttachment] | None = None,
        reply_to: str | None = None,
    ) -> str:
        """Envoie un email et retourne son Message-ID. Lève ExternalServiceError si échec."""
        if not self.is_configured:
            raise ExternalServiceError("SMTP is not configured", code="EMAIL_NOT_CONFIGURED")
        message = EmailMessage()
        message["From"] = self.settings.SMTP_FROM
        message["To"] = to
        message["Subject"] = subject
        message["Message-ID"] = make_msgid(domain=(self.settings.SMTP_FROM or "").split("@")[-1])
        if reply_to:
            message["Reply-To"] = reply_to
        message.set_content(text_body)
        if html_body:
            message.add_alternative(html_body, subtype="html")
        for attachment in attachments or []:
            maintype, _, subtype = attachment.mime_type.partition("/")
            message.add_attachment(
                attachment.content,
                maintype=maintype or "application",
                subtype=subtype or "octet-stream",
                filename=attachment.filename,
            )

        try:
            self._deliver(message)
        except (smtplib.SMTPException, OSError) as exc:
            logger.error("Email sending failed: %s", type(exc).__name__)
            raise ExternalServiceError("Email sending failed", code="EMAIL_ERROR") from None
        logger.info("Email sent", extra={"subject": subject[:80]})
        return str(message["Message-ID"])

    def _deliver(self, message: EmailMessage) -> None:
        settings = self.settings
        host = settings.SMTP_HOST or ""
        timeout = settings.SMTP_TIMEOUT_SECONDS
        context = ssl.create_default_context()
        smtp: smtplib.SMTP
        if settings.SMTP_USE_SSL:
            smtp = smtplib.SMTP_SSL(host, settings.SMTP_PORT, timeout=timeout, context=context)
        else:
            smtp = smtplib.SMTP(host, settings.SMTP_PORT, timeout=timeout)
        with smtp:
            if settings.SMTP_USE_TLS and not settings.SMTP_USE_SSL:
                smtp.starttls(context=context)
            if settings.SMTP_USERNAME and settings.SMTP_PASSWORD:
                smtp.login(settings.SMTP_USERNAME, settings.SMTP_PASSWORD.get_secret_value())
            smtp.send_message(message)

    # --- Emails métier ---

    def send_new_job_email(self, to: str, data: dict[str, Any], high_match: bool = False) -> None:
        subject, text, html = templates.new_job_email(data, high_match=high_match)
        self.send_email(to, subject, text, html)

    def send_recruiter_response_email(self, to: str, data: dict[str, Any]) -> None:
        subject, text, html = templates.recruiter_response_email(data)
        self.send_email(to, subject, text, html)

    def send_application_status_email(self, to: str, data: dict[str, Any]) -> None:
        subject, text, html = templates.application_status_email(data)
        self.send_email(to, subject, text, html)

    def send_error_email(self, to: str, title: str, message: str) -> None:
        subject, text, html = templates.error_email(title, message)
        self.send_email(to, subject, text, html)

    def send_notification(
        self, to: str, notification_type: NotificationType, title: str, message: str,
        data: dict[str, Any],
    ) -> None:  # fmt: skip
        """Choisit le bon gabarit selon le type de notification."""
        match notification_type:
            case NotificationType.NEW_JOB if data.get("job_id"):
                self.send_new_job_email(to, data)
            case NotificationType.HIGH_MATCH:
                self.send_new_job_email(to, data, high_match=True)
            case NotificationType.RECRUITER_RESPONSE:
                self.send_recruiter_response_email(to, data)
            case NotificationType.APPLICATION_STATUS:
                self.send_application_status_email(to, data)
            case NotificationType.SCRAPING_ERROR | NotificationType.MONITORING:
                self.send_error_email(to, title, message)
            case _:
                subject, text, html = templates.generic_email(title, message)
                self.send_email(to, subject, text, html)
