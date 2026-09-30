"""Gestion des candidatures (UML 12, 16, 18 / RG-10).

Parcours type :
1. POST /applications                 -> NOT_APPLIED ou PREPARING
2. POST /applications/{id}/prepare    -> brouillons (lettre, email) + choix du CV -> READY
3. Flutter affiche le brouillon et demande confirmation à l'utilisateur
4. POST /applications/{id}/submit     -> confirm=true obligatoire -> SUBMITTED
5. Suivi : FOLLOW_UP, INTERVIEW, OFFER, REJECTED, WITHDRAWN (manuel ou via n8n)
"""

import logging
import uuid
from datetime import timedelta
from typing import Any

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError, ConflictError, NotFoundError
from app.modules.ai.schemas import GenerationKind
from app.modules.ai.service import AIService
from app.modules.applications import rules
from app.modules.applications.models import Application, ApplicationStatusHistory, RecruiterResponse
from app.modules.applications.repository import (
    ApplicationHistoryRepository,
    ApplicationRepository,
    RecruiterResponseRepository,
)
from app.modules.applications.schemas import (
    ApplicationCreate,
    ApplicationUpdate,
    GenerateRequest,
    PrepareRequest,
    SubmitRequest,
)
from app.modules.audit.service import AuditService
from app.modules.documents.models import Document
from app.modules.documents.service import DocumentService
from app.modules.integrations.email.service import EmailAttachment, EmailService
from app.modules.jobs.models import Job
from app.modules.notifications.service import NotificationService
from app.modules.profile.repository import ProfileRepository
from app.modules.realtime.events import EventType, publish_event
from app.modules.skills.repository import ProfileSkillRepository
from app.modules.users.models import User
from app.shared.enums import (
    ActorType,
    ApplicationStatus,
    DocumentType,
    NotificationType,
    SubmissionMethod,
)
from app.shared.pagination import PaginationParams
from app.shared.utils import utcnow

logger = logging.getLogger("app.applications")

STATUS_LABELS = {
    ApplicationStatus.NOT_APPLIED: "non envoyée",
    ApplicationStatus.PREPARING: "en préparation",
    ApplicationStatus.READY: "prête à envoyer",
    ApplicationStatus.SUBMITTED: "envoyée",
    ApplicationStatus.FOLLOW_UP: "à relancer",
    ApplicationStatus.INTERVIEW: "entretien",
    ApplicationStatus.OFFER: "offre reçue",
    ApplicationStatus.REJECTED: "refusée",
    ApplicationStatus.WITHDRAWN: "retirée",
}


class ApplicationService:
    """Candidatures de l'utilisateur et leur cycle de vie."""

    def __init__(self, session: Session) -> None:
        self.session = session
        self.applications = ApplicationRepository(session)
        self.history = ApplicationHistoryRepository(session)
        self.audit = AuditService(session)

    # --- CRUD ---

    def create(self, user: User, data: ApplicationCreate) -> Application:
        if data.status not in rules.INITIAL_STATUSES:
            raise BusinessRuleError(
                "A new application must start as not_applied or preparing",
                code="INVALID_INITIAL_STATUS",
            )
        job = None
        if data.job_id:
            job = self.session.get(Job, data.job_id)
            if job is None:
                raise NotFoundError("Job not found", code="JOB_NOT_FOUND")
            if self.applications.get_active_for_job(user.id, job.id):
                raise ConflictError(
                    "You already have an active application for this job",
                    code="APPLICATION_ALREADY_EXISTS",
                )
        self._check_document(user, data.cv_document_id, DocumentType.CV)

        application = Application(
            user_id=user.id,
            job_id=job.id if job else None,
            job_title=(data.job_title or (job.title if job else ""))[:500],
            company_name=data.company_name or (job.company.name if job and job.company else None),
            status=data.status,
            cv_document_id=data.cv_document_id,
            notes=data.notes,
            follow_up_at=data.follow_up_at,
        )
        try:
            self.applications.add(application)
        except IntegrityError as exc:  # course entre deux créations simultanées
            self.session.rollback()
            raise ConflictError(
                "You already have an active application for this job",
                code="APPLICATION_ALREADY_EXISTS",
            ) from exc
        self._record_history(
            application, None, application.status, ActorType.USER, user.id, "Création"
        )
        self.session.commit()
        return application

    def list_applications(
        self, user: User, pagination: PaginationParams, status: ApplicationStatus | None = None,
        job_id: uuid.UUID | None = None,
    ) -> tuple[list[Application], int]:  # fmt: skip
        return self.applications.paginate(
            self.applications.list_query(user.id, status, job_id), pagination
        )

    def get(self, user: User, application_id: uuid.UUID) -> Application:
        application = self.applications.get_for_user(application_id, user.id)
        if application is None:
            raise NotFoundError("Application not found", code="APPLICATION_NOT_FOUND")
        return application

    def update(self, user: User, application_id: uuid.UUID, data: ApplicationUpdate) -> Application:
        application = self.get(user, application_id)
        updates = data.model_dump(exclude_unset=True)
        if "cv_document_id" in updates:
            self._check_document(user, updates["cv_document_id"], DocumentType.CV)
        if "cover_letter_document_id" in updates:
            self._check_document(
                user, updates["cover_letter_document_id"], DocumentType.COVER_LETTER
            )
        for field, value in updates.items():
            setattr(application, field, value)
        self.session.commit()
        return application

    def delete(self, user: User, application_id: uuid.UUID) -> None:
        application = self.get(user, application_id)
        if application.status == ApplicationStatus.SUBMITTED:
            raise BusinessRuleError(
                "A submitted application cannot be deleted; mark it as withdrawn instead",
                code="APPLICATION_ALREADY_SUBMITTED",
            )
        self.applications.delete(application)
        self.session.commit()

    def get_history(self, user: User, application_id: uuid.UUID) -> list[ApplicationStatusHistory]:
        return self.history.list_for_application(self.get(user, application_id).id)

    # --- Cycle de vie ---

    def change_status(
        self,
        application: Application,
        target: ApplicationStatus,
        *,
        actor_type: ActorType,
        actor_id: uuid.UUID | None,
        note: str | None = None,
    ) -> Application:
        """Change le statut en respectant la machine à états (appelé par Flutter et n8n)."""
        current = ApplicationStatus(application.status)
        if current == target:
            return (
                application  # idempotent : un webhook reçu deux fois ne fait rien de plus (RG-18)
            )
        if not rules.actor_may_set(actor_type, target):
            code = (
                "SUBMIT_REQUIRES_CONFIRMATION"
                if target in rules.SUBMIT_ONLY
                else "STATUS_NOT_ALLOWED"
            )
            raise BusinessRuleError(f"Status '{target.value}' cannot be set this way", code=code)
        if not rules.can_transition(current, target):
            raise BusinessRuleError(
                f"Invalid status transition: {current.value} -> {target.value}",
                code="INVALID_STATUS_TRANSITION",
                details={
                    "allowed": sorted(status.value for status in rules.ALLOWED_TRANSITIONS[current])
                },
            )
        now = utcnow()
        application.status = target
        if target in {
            ApplicationStatus.INTERVIEW,
            ApplicationStatus.OFFER,
            ApplicationStatus.REJECTED,
        }:
            application.response_received_at = application.response_received_at or now
            application.last_contact_at = now
        self._record_history(application, current, target, actor_type, actor_id, note)
        self.session.commit()
        self._notify_status(application)
        return application

    def change_status_for_user(
        self, user: User, application_id: uuid.UUID, target: ApplicationStatus, note: str | None
    ) -> Application:
        application = self.get(user, application_id)
        return self.change_status(
            application, target, actor_type=ActorType.USER, actor_id=user.id, note=note
        )

    def prepare(self, user: User, application_id: uuid.UUID, data: PrepareRequest) -> Application:
        """UML 12 : brouillons générés + CV choisi, puis statut READY (rien n'est envoyé)."""
        application = self.get(user, application_id)
        if application.status not in {ApplicationStatus.NOT_APPLIED, ApplicationStatus.PREPARING}:
            raise BusinessRuleError(
                "Only a draft application can be prepared", code="APPLICATION_NOT_DRAFT"
            )

        documents = DocumentService(self.session)
        if application.cv_document_id is None:
            cv = documents.choose_cv(user, data.language, application.job_title)
            application.cv_document_id = cv.id if cv else None

        ai = AIService(self.session)
        candidate = self._candidate_context(user)
        description = application.job.description if application.job else None
        if data.generate_cover_letter and not application.cover_letter_text:
            letter = ai.generate_application(
                GenerationKind.COVER_LETTER,
                candidate,
                application.job_title,
                application.company_name,
                description,
            )
            application.cover_letter_text = letter["content"]
        if data.generate_email and not application.email_body:
            email = ai.generate_application(
                GenerationKind.APPLICATION_EMAIL,
                candidate,
                application.job_title,
                application.company_name,
                description,
            )
            application.email_subject = email["subject"]
            application.email_body = email["content"]

        if application.status == ApplicationStatus.NOT_APPLIED:
            self._record_history(
                application,
                ApplicationStatus.NOT_APPLIED,
                ApplicationStatus.PREPARING,
                ActorType.USER,
                user.id,
                None,
            )
        previous = ApplicationStatus.PREPARING
        application.status = ApplicationStatus.READY
        self._record_history(
            application,
            previous,
            ApplicationStatus.READY,
            ActorType.USER,
            user.id,
            "Brouillons générés",
        )
        self.session.commit()
        self._notify_status(application)
        return application

    def generate(
        self, user: User, application_id: uuid.UUID, data: GenerateRequest
    ) -> dict[str, Any]:
        """Génère un texte (lettre, email, résumé, réponse recruteur) pour cette candidature."""
        application = self.get(user, application_id)
        context: dict[str, Any] = {}
        if data.kind == GenerationKind.RECRUITER_REPLY:
            response = self._get_response(user, data.response_id) if data.response_id else None
            if response is None:
                raise BusinessRuleError(
                    "response_id is required for a recruiter reply", code="RESPONSE_REQUIRED"
                )
            context = {
                "recruiter_message": response.body or "",
                "response_type": response.response_type,
            }
        description = application.job.description if application.job else None
        result = AIService(self.session).generate_application(
            data.kind, self._candidate_context(user), application.job_title, application.company_name,
            description, context,
        )  # fmt: skip
        if data.save:
            if data.kind == GenerationKind.COVER_LETTER:
                application.cover_letter_text = result["content"]
            elif data.kind == GenerationKind.APPLICATION_EMAIL:
                application.email_subject = result["subject"]
                application.email_body = result["content"]
            self.session.commit()
        return result

    def submit(self, user: User, application_id: uuid.UUID, data: SubmitRequest) -> Application:
        """Envoi validé explicitement par l'utilisateur (RG-10) : READY -> SUBMITTED."""
        application = self.get(user, application_id)
        if not data.confirm:
            raise BusinessRuleError(
                "Explicit confirmation is required (confirm=true)", code="CONFIRMATION_REQUIRED"
            )
        if application.status == ApplicationStatus.SUBMITTED:
            raise ConflictError(
                "This application has already been submitted", code="APPLICATION_ALREADY_SUBMITTED"
            )
        if application.status != ApplicationStatus.READY:
            raise BusinessRuleError(
                "Only a READY application can be submitted", code="APPLICATION_NOT_READY"
            )

        method = data.method or SubmissionMethod.WEBSITE
        reference = data.reference
        if data.send_email:
            reference = self._send_application_email(user, application, data.to_email)
            method = SubmissionMethod.EMAIL

        now = utcnow()
        application.status = ApplicationStatus.SUBMITTED
        application.submitted_at = now
        application.submission_method = method
        application.submission_reference = reference
        application.follow_up_at = application.follow_up_at or now + timedelta(
            days=rules.FOLLOW_UP_AFTER_DAYS
        )
        self._record_history(
            application, ApplicationStatus.READY, ApplicationStatus.SUBMITTED, ActorType.USER, user.id,
            f"Envoi confirmé ({method.value})",
        )  # fmt: skip
        self.audit.record(
            "application.submitted", actor_type=ActorType.USER, actor_id=user.id,
            entity_type="application", entity_id=application.id, details={"method": method.value},
        )  # fmt: skip
        self.session.commit()
        self._notify_status(application)
        return application

    def follow_ups_due(self) -> list[Application]:
        return self.applications.follow_ups_due(utcnow())

    # --- Interne ---

    def _send_application_email(
        self, user: User, application: Application, to_email: str | None
    ) -> str:
        recipient = to_email or (application.job.application_email if application.job else None)
        if not recipient:
            raise BusinessRuleError(
                "No recipient email for this application", code="NO_APPLICATION_EMAIL"
            )
        if not (application.email_subject and application.email_body):
            raise BusinessRuleError(
                "Email subject and body are required", code="EMAIL_DRAFT_MISSING"
            )
        email_service = EmailService()
        if not email_service.is_configured:
            raise BusinessRuleError("SMTP is not configured", code="EMAIL_NOT_CONFIGURED")

        attachments = []
        documents = DocumentService(self.session)
        for document_id in (application.cv_document_id, application.cover_letter_document_id):
            if document_id:
                document = documents.get(user, document_id)
                attachments.append(
                    EmailAttachment(
                        document.original_filename,
                        documents.read_content(document),
                        document.mime_type,
                    )
                )
        profile = ProfileRepository(self.session).get_by_user(user.id)
        reply_to = (profile.email if profile and profile.email else None) or user.email
        return email_service.send_email(
            recipient,
            application.email_subject,
            application.email_body,
            attachments=attachments,
            reply_to=reply_to,
        )

    def _record_history(
        self,
        application: Application,
        from_status: ApplicationStatus | None,
        to_status: ApplicationStatus,
        actor_type: ActorType,
        actor_id: uuid.UUID | None,
        note: str | None,
    ) -> None:
        self.session.add(
            ApplicationStatusHistory(
                application_id=application.id,
                from_status=from_status,
                to_status=to_status,
                note=note,
                actor_type=actor_type,
                actor_id=actor_id,
            )
        )
        if from_status is not None:
            self.audit.record(
                "application.status_changed", actor_type=actor_type, actor_id=actor_id,
                entity_type="application", entity_id=application.id,
                details={"from": from_status.value, "to": to_status.value},
            )  # fmt: skip

    def _notify_status(self, application: Application) -> None:
        status = ApplicationStatus(application.status)
        data = {
            "application_id": str(application.id),
            "job_id": str(application.job_id) if application.job_id else None,
            "job_title": application.job_title,
            "company_name": application.company_name,
            "status": status.value,
        }
        publish_event(EventType.APPLICATION_STATUS, data, application.user_id)
        NotificationService(self.session).notify(
            application.user_id,
            NotificationType.APPLICATION_STATUS,
            f"Candidature {STATUS_LABELS[status]} : {application.job_title}"[:255],
            f"{application.job_title} — {application.company_name or 'entreprise non précisée'}",
            data=data,
        )

    def _check_document(
        self, user: User, document_id: uuid.UUID | None, expected: DocumentType
    ) -> Document | None:
        if document_id is None:
            return None
        document = DocumentService(self.session).get(user, document_id)
        if document.document_type != expected:
            raise BusinessRuleError(
                f"The document must be of type {expected.value}", code="INVALID_DOCUMENT_TYPE"
            )
        return document

    def _get_response(self, user: User, response_id: uuid.UUID) -> RecruiterResponse | None:
        return RecruiterResponseRepository(self.session).get_for_user(response_id, user.id)

    def _candidate_context(self, user: User) -> dict[str, Any]:
        """Faits sur le candidat transmis à la génération (jamais inventés)."""
        profile = ProfileRepository(self.session).get_by_user(user.id)
        if profile is None:
            return {"email": user.email}
        skills = ProfileSkillRepository(self.session).list_for_profile(
            profile.id, enabled_only=True
        )
        return {
            "full_name": profile.full_name,
            "professional_title": profile.professional_title,
            "years_of_experience": profile.years_of_experience,
            "city": profile.city,
            "bio": profile.bio,
            "skills": [item.skill.name for item in skills],
            "languages": ", ".join(profile.language_codes),
            "email": profile.email or user.email,
            "phone": profile.phone,
            "linkedin_url": profile.linkedin_url,
        }
