"""Étape DEDUPLICATE du pipeline (RG-05 / RG-18).

Une même offre peut arriver plusieurs fois (même source relancée, ou autre site).
On cherche une offre existante, du critère le plus sûr au moins sûr :

1. même source + même identifiant externe ;
2. même URL (normalisée : sans paramètres de tracking) ;
3. même empreinte (titre + entreprise + ville normalisés) ;
4. titre très similaire (>= 85 %) chez la même entreprise, publié récemment,
   au même endroit (ou en télétravail).
"""

import uuid
from dataclasses import dataclass
from datetime import timedelta
from difflib import SequenceMatcher

from sqlalchemy.orm import Session

from app.modules.jobs.models import Job
from app.modules.jobs.repository import JobRepository
from app.modules.scraping.schemas import NormalizedJob
from app.shared.geo import same_place
from app.shared.utils import utcnow

SIMILARITY_THRESHOLD = 0.85
SIMILARITY_WINDOW_DAYS = 45


@dataclass
class DuplicateMatch:
    job: Job
    method: str  # "external_id", "url", "fingerprint" ou "similarity"


class DeduplicationService:
    def __init__(self, session: Session) -> None:
        self.jobs = JobRepository(session)

    def find_duplicate(
        self, job: NormalizedJob, source_id: uuid.UUID, company_id: uuid.UUID | None
    ) -> DuplicateMatch | None:
        if job.external_id:
            existing = self.jobs.find_by_source_external_id(source_id, job.external_id)
            if existing:
                return DuplicateMatch(existing, "external_id")
        for url in (job.source_url, job.application_url):
            if url:
                existing = self.jobs.find_by_url(url)
                if existing:
                    return DuplicateMatch(existing, "url")
        existing = self.jobs.find_by_fingerprint(job.fingerprint)
        if existing:
            return DuplicateMatch(existing, "fingerprint")
        if company_id:
            similar = self._find_similar(job, company_id)
            if similar:
                return DuplicateMatch(similar, "similarity")
        return None

    def _find_similar(self, job: NormalizedJob, company_id: uuid.UUID) -> Job | None:
        since = utcnow() - timedelta(days=SIMILARITY_WINDOW_DAYS)
        for candidate in self.jobs.similarity_candidates(company_id, since):
            if not self._same_place(job, candidate):
                continue
            ratio = SequenceMatcher(None, job.normalized_title, candidate.normalized_title).ratio()
            if ratio >= SIMILARITY_THRESHOLD:
                return candidate
        return None

    @staticmethod
    def _same_place(job: NormalizedJob, candidate: Job) -> bool:
        if job.is_remote or candidate.is_remote:
            return True
        if not job.city or not candidate.city:
            return True
        return same_place(job.city, candidate.city)
