"""CorrelationService : retrouve la candidature concernée par une réponse reçue (UML 13, RG-14).

Stratégie "contrôlée" : on n'associe une réponse que si le résultat est sans ambiguïté.
1. `application_id` fourni (n8n peut le connaître grâce à un identifiant dans l'email) ;
2. l'expéditeur est le recruteur de l'offre ;
3. le domaine de l'expéditeur est celui de l'entreprise (site web ou email de candidature),
   hors messageries publiques (gmail, outlook...) ;
4. l'objet de l'email contient le titre du poste.
Si plusieurs candidatures correspondent, on ne choisit pas au hasard : pas d'association.
"""

import uuid
from dataclasses import dataclass

from sqlalchemy.orm import Session

from app.modules.applications.models import Application
from app.modules.applications.repository import ApplicationRepository
from app.shared.utils import email_domain, normalize_text, url_domain

PUBLIC_EMAIL_DOMAINS = {
    "gmail.com", "googlemail.com", "outlook.com", "outlook.fr", "hotmail.com", "hotmail.fr",
    "live.com", "live.fr", "yahoo.com", "yahoo.fr", "icloud.com", "me.com", "proton.me",
    "protonmail.com", "gmx.com", "gmx.fr", "orange.fr", "free.fr", "laposte.net", "aol.com",
}  # fmt: skip


@dataclass
class Correlation:
    application: Application | None
    method: str  # application_id, recruiter_email, company_domain, subject ou none


class CorrelationService:
    def __init__(self, session: Session) -> None:
        self.applications = ApplicationRepository(session)

    def find_application(
        self,
        *,
        application_id: uuid.UUID | None,
        sender_email: str,
        subject: str | None,
        user_id: uuid.UUID | None,
    ) -> Correlation:
        if application_id:
            application = self.applications.get(application_id)
            if application and (user_id is None or application.user_id == user_id):
                return Correlation(application, "application_id")

        candidates = self.applications.list_active(user_id)
        sender = sender_email.strip().lower()

        by_recruiter = [
            app for app in candidates
            if app.job and app.job.recruiter and (app.job.recruiter.email or "").lower() == sender
        ]  # fmt: skip
        if len(by_recruiter) == 1:
            return Correlation(by_recruiter[0], "recruiter_email")

        domain = email_domain(sender)
        if domain and domain not in PUBLIC_EMAIL_DOMAINS:
            by_domain = [app for app in candidates if domain in _company_domains(app)]
            if len(by_domain) == 1:
                return Correlation(by_domain[0], "company_domain")

        normalized_subject = f" {normalize_text(subject)} "
        by_subject = [
            app for app in candidates
            if normalize_text(app.job_title) and f" {normalize_text(app.job_title)} " in normalized_subject
        ]  # fmt: skip
        if len(by_subject) == 1:
            return Correlation(by_subject[0], "subject")
        return Correlation(None, "none")


def _company_domains(application: Application) -> set[str]:
    job = application.job
    if job is None:
        return set()
    # (pas le domaine de l'URL de candidature : souvent un job board partagé par plusieurs offres)
    domains = {email_domain(job.application_email)}
    if job.company:
        domains |= {url_domain(job.company.website), email_domain(job.company.email)}
    if job.recruiter:
        domains.add(email_domain(job.recruiter.email))
    return {domain for domain in domains if domain and domain not in PUBLIC_EMAIL_DOMAINS}
