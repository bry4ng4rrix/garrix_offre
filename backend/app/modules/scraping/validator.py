"""Étape VALIDATE du pipeline (RG-08).

- Offre INVALIDE (rejetée) : titre inexploitable, aucun identifiant (URL ou id externe),
  date de publication dans le futur, offre déjà expirée.
- Offre INCOMPLÈTE (enregistrée avec le statut NEW) : pas de description, pas d'entreprise,
  pas de lieu... La liste des problèmes est gardée dans `quality_issues`.
"""

from dataclasses import dataclass, field
from datetime import timedelta

from app.modules.scraping.schemas import NormalizedJob
from app.shared.utils import utcnow

MIN_TITLE_LENGTH = 3
MIN_DESCRIPTION_LENGTH = 50


@dataclass
class ValidationOutcome:
    errors: list[str] = field(default_factory=list)
    quality_issues: list[str] = field(default_factory=list)

    @property
    def is_valid(self) -> bool:
        return not self.errors

    @property
    def is_complete(self) -> bool:
        return not self.quality_issues


class JobValidator:
    """Décide si une offre normalisée peut être enregistrée, et si elle est complète."""

    def validate(self, job: NormalizedJob) -> ValidationOutcome:
        outcome = ValidationOutcome()
        now = utcnow()

        if len(job.normalized_title) < MIN_TITLE_LENGTH:
            outcome.errors.append("invalid_title")
        if not (job.source_url or job.external_id or job.application_url):
            outcome.errors.append("missing_identifier")
        if job.published_at and job.published_at > now + timedelta(days=2):
            outcome.errors.append("published_in_future")
        if job.expires_at and job.expires_at < now:
            outcome.errors.append("already_expired")

        if not job.description or len(job.description) < MIN_DESCRIPTION_LENGTH:
            outcome.quality_issues.append("missing_description")
        if not job.company_name:
            outcome.quality_issues.append("missing_company")
        if not (job.city or job.country or job.is_remote):
            outcome.quality_issues.append("missing_location")
        if job.expires_at and job.published_at and job.expires_at < job.published_at:
            outcome.quality_issues.append("expires_before_published")
        return outcome
