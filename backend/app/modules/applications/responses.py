"""Réception des réponses de recruteurs (UML 13 / RG-14).

Email -> n8n -> POST /webhooks/n8n/recruiter-response -> ici :
1. idempotence : un même email (Message-ID) n'est enregistré qu'une fois (RG-18) ;
2. corrélation avec une candidature (CorrelationService) ;
3. analyse du type de réponse (IA si configurée, sinon règles) ;
4. enregistrement du message original et des métadonnées ;
5. notification (base + WebSocket + Telegram/Email selon les préférences).

Le statut de la candidature n'est PAS modifié automatiquement : l'analyse propose un
`suggested_status` que l'utilisateur (ou un workflow n8n explicite) applique.
"""

import logging
import uuid
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError
from app.modules.ai.service import AIService
from app.modules.applications.correlation import CorrelationService
from app.modules.applications.models import RecruiterResponse
from app.modules.applications.repository import (
    ApplicationRepository,
    RecruiterResponseRepository,
)
from app.modules.applications.schemas import RecruiterResponseUpdate
from app.modules.notifications.service import NotificationService
from app.modules.realtime.events import EventType, publish_event
from app.modules.users.models import User
from app.modules.users.repository import UserRepository
from app.shared.enums import NotificationType, RecruiterResponseType
from app.shared.pagination import PaginationParams
from app.shared.utils import utcnow

logger = logging.getLogger("app.applications")


@dataclass
class ReceivedResponse:
    response: RecruiterResponse
    duplicate: bool


class RecruiterResponseService:
    def __init__(self, session: Session) -> None:
        self.session = session
        self.responses = RecruiterResponseRepository(session)

    def receive(
        self,
        *,
        sender_email: str,
        subject: str | None,
        body: str | None,
        received_at: datetime | None,
        sender_name: str | None = None,
        application_id: uuid.UUID | None = None,
        message_id: str | None = None,
        user: User | None = None,
    ) -> ReceivedResponse:
        if message_id:
            existing = self.responses.get_by_message_id(message_id)
            if existing:
                return ReceivedResponse(existing, duplicate=True)

        correlation = CorrelationService(self.session).find_application(
            application_id=application_id,
            sender_email=sender_email,
            subject=subject,
            user_id=user.id if user else None,
        )
        application = correlation.application
        owner_id = (
            application.user_id if application else (user.id if user else self._single_user_id())
        )

        analysis = AIService(self.session).analyze_recruiter_response(subject, body)
        response = self.responses.add(
            RecruiterResponse(
                user_id=owner_id,
                application_id=application.id if application else None,
                message_id=message_id,
                sender_email=sender_email.lower(),
                sender_name=sender_name,
                subject=subject,
                body=body,
                received_at=received_at or utcnow(),
                response_type=RecruiterResponseType(analysis["response_type"]),
                correlation_method=correlation.method,
                analysis=analysis,
            )
        )
        if application:
            application.last_contact_at = response.received_at
            application.response_received_at = (
                application.response_received_at or response.received_at
            )
        self.session.commit()
        logger.info(
            "Recruiter response received",
            extra={"correlation": correlation.method, "type": response.response_type.value},
        )
        self._notify(response, application.job_title if application else None)
        return ReceivedResponse(response, duplicate=False)

    def list_responses(
        self, user: User, pagination: PaginationParams, application_id: uuid.UUID | None = None
    ) -> tuple[list[RecruiterResponse], int]:
        return self.responses.paginate(
            self.responses.list_query(user.id, application_id), pagination
        )

    def update(
        self, user: User, response_id: uuid.UUID, data: RecruiterResponseUpdate
    ) -> RecruiterResponse:
        response = self.responses.get_for_user(response_id, user.id)
        if response is None:
            raise NotFoundError("Recruiter response not found", code="RECRUITER_RESPONSE_NOT_FOUND")
        updates = data.model_dump(exclude_unset=True)
        if updates.get("application_id"):
            application = ApplicationRepository(self.session).get_for_user(
                updates["application_id"], user.id
            )
            if application is None:
                raise NotFoundError("Application not found", code="APPLICATION_NOT_FOUND")
            response.correlation_method = "manual"
        for field, value in updates.items():
            setattr(response, field, value)
        self.session.commit()
        return response

    def _single_user_id(self) -> uuid.UUID | None:
        """Instance personnelle : s'il n'y a qu'un seul compte actif, la réponse lui revient."""
        users = UserRepository(self.session).list_active()
        return users[0].id if len(users) == 1 else None

    def _notify(self, response: RecruiterResponse, job_title: str | None) -> None:
        data = {
            "response_id": str(response.id),
            "application_id": str(response.application_id) if response.application_id else None,
            "sender_email": response.sender_email,
            "subject": response.subject,
            "response_type": response.response_type.value,
            "suggested_status": response.analysis.get("suggested_status"),
            "job_title": job_title,
        }
        title = f"Réponse recruteur : {response.subject or response.sender_email}"[:255]
        message = response.analysis.get("summary") or (response.body or "")[:300]
        notifications = NotificationService(self.session)
        if response.user_id:
            publish_event(EventType.RECRUITER_RESPONSE, data, response.user_id)
            notifications.notify(
                response.user_id, NotificationType.RECRUITER_RESPONSE, title, message, data
            )
        else:
            notifications.notify_admins(NotificationType.RECRUITER_RESPONSE, title, message, data)
