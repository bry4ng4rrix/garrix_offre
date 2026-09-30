import logging
import uuid
from dataclasses import dataclass, field

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.exceptions import NotFoundError
from app.modules.audit.service import AuditService
from app.modules.experiences.repository import (
    ExperienceLevelRepository,
    ExperiencePreferenceRepository,
    ExperienceRepository,
)
from app.modules.job_titles.repository import JobTitleRepository
from app.modules.jobs.models import Job
from app.modules.matching.models import JobMatch, MatchingSettings
from app.modules.matching.repository import JobMatchRepository, MatchingSettingsRepository
from app.modules.matching.schemas import MatchingSettingsUpdate
from app.modules.matching.scoring import (
    CandidateProfile,
    CandidateSkill,
    JobCriteria,
    LocationWish,
    MatchingWeights,
    MatchResult,
    TechnologyPreference,
    compute_match,
)
from app.modules.preferences.repository import SearchPreferenceRepository
from app.modules.profile.repository import ProfileRepository
from app.modules.realtime.events import EventType, publish_event
from app.modules.skills.repository import ProfileSkillRepository
from app.modules.users.models import User
from app.modules.users.repository import UserRepository
from app.shared.enums import ActorType, JobStatus, SkillRequirement

logger = logging.getLogger("app.matching")

BATCH_SIZE = 200
WEIGHT_FIELDS = (
    "skills", "experience", "contract", "location", "salary", "language", "title",
    "experience_level",
)  # fmt: skip


@dataclass
class MatchingContext:
    """Tout ce qu'il faut pour calculer les scores d'un utilisateur (chargé une seule fois)."""

    user_id: uuid.UUID
    profile: CandidateProfile
    weights: MatchingWeights
    threshold: int
    level_ranks: dict[str, int] = field(default_factory=dict)


@dataclass
class ScoredJob:
    job: Job
    result: MatchResult


class MatchingService:
    """Compare les offres au profil et aux préférences, puis enregistre les résultats.

    Le calcul lui-même est dans scoring.py (fonctions pures) ; ce service s'occupe de
    charger les données, d'appeler le calcul et de sauvegarder les résultats.
    Il fonctionne entièrement sans IA (RG-09).
    """

    def __init__(self, session: Session) -> None:
        self.session = session
        self.matches = JobMatchRepository(session)
        self.settings_repository = MatchingSettingsRepository(session)

    # --- Chargement des données ---

    def load_context(self, user_id: uuid.UUID) -> MatchingContext:
        preference = SearchPreferenceRepository(self.session).get_or_create(user_id)
        profile = ProfileRepository(self.session).get_by_user(user_id)
        skills = (
            ProfileSkillRepository(self.session).list_for_profile(profile.id, True)
            if profile
            else []
        )
        technologies = ExperiencePreferenceRepository(self.session).list_for_user(user_id, True)
        titles = JobTitleRepository(self.session).list_for_user(user_id, enabled_only=True)

        years = profile.years_of_experience if profile else None
        if years is None and profile:
            experiences = ExperienceRepository(self.session).list_for_profile(profile.id)
            years = round(sum(item.duration_years for item in experiences)) if experiences else None

        candidate = CandidateProfile(
            skills=[CandidateSkill(item.skill.name, item.level) for item in skills],
            technologies=[
                TechnologyPreference(item.skill.name, item.priority, item.is_required)
                for item in technologies
            ],
            job_titles=[item.title for item in titles],
            contract_types=preference.contract_type_codes,
            experience_levels=preference.experience_levels,
            experience_level=profile.experience_level if profile else None,
            years_of_experience=years,
            locations=[
                LocationWish(loc.get("city"), loc.get("country")) for loc in preference.locations
            ],
            city=profile.city if profile else None,
            country=profile.country if profile else None,
            accepts_remote=preference.remote,
            accepts_hybrid=preference.hybrid,
            accepts_onsite=preference.onsite,
            minimum_salary=preference.minimum_salary,
            salary_currency=preference.currency,
            salary_period=preference.salary_period,
            languages=preference.languages or (profile.language_codes if profile else []),
        )
        return MatchingContext(
            user_id=user_id,
            profile=candidate,
            weights=self._weights(self.settings_repository.get_or_create(user_id)),
            threshold=preference.matching_threshold,
            level_ranks=ExperienceLevelRepository(self.session).ranks_by_code(),
        )

    @staticmethod
    def job_criteria(job: Job) -> JobCriteria:
        return JobCriteria(
            title=job.title,
            skills=[(item.skill.name, SkillRequirement(item.requirement)) for item in job.skills],
            contract_type=job.contract_type,
            experience_level=job.experience_level,
            min_years_experience=job.min_years_experience,
            city=job.city,
            country=job.country,
            is_remote=job.is_remote,
            is_hybrid=job.is_hybrid,
            salary_min=job.salary_min,
            salary_max=job.salary_max,
            salary_currency=job.salary_currency,
            salary_period=job.salary_period,
            languages=job.languages,
        )

    # --- Calcul ---

    def score(self, context: MatchingContext, job: Job) -> MatchResult:
        return compute_match(
            context.profile, self.job_criteria(job), context.weights, context.level_ranks
        )

    def match_job(self, user: User, job_id: uuid.UUID) -> JobMatch:
        """POST /jobs/{job_id}/match : recalcule et retourne le résultat pour cette offre."""
        job = self.session.get(Job, job_id)
        if job is None:
            raise NotFoundError("Job not found", code="JOB_NOT_FOUND")
        context = self.load_context(user.id)
        self.matches.upsert(user.id, job.id, self.score(context, job))
        self.session.commit()
        match = self.matches.get_for_job(user.id, job.id)
        assert match is not None  # noqa: S101 - la ligne vient d'être écrite
        self.session.refresh(match)
        return match

    def match_jobs_for_all_users(self, jobs: list[Job]) -> dict[uuid.UUID, list[ScoredJob]]:
        """Étape MATCH du pipeline : score des nouvelles offres pour chaque utilisateur actif.

        Retourne, par utilisateur, les offres dont le score atteint son seuil (high match).
        """
        high_matches: dict[uuid.UUID, list[ScoredJob]] = {}
        if not jobs:
            return high_matches
        for user in UserRepository(self.session).list_active():
            context = self.load_context(user.id)
            for job in jobs:
                result = self.score(context, job)
                self.matches.upsert(user.id, job.id, result)
                if result.score >= context.threshold:
                    high_matches.setdefault(user.id, []).append(ScoredJob(job, result))
        self.session.commit()
        logger.info(
            "Jobs matched", extra={"jobs": len(jobs), "high_match_users": len(high_matches)}
        )
        return high_matches

    def recalculate_for_user(
        self, user_id: uuid.UUID, actor_type: ActorType = ActorType.USER
    ) -> int:
        """Recalcule les scores de toutes les offres actives (après une modification du profil)."""
        context = self.load_context(user_id)
        stmt = (
            select(Job)
            .where(Job.status.in_([JobStatus.NEW, JobStatus.ACTIVE]))
            .order_by(Job.id)
            .execution_options(yield_per=BATCH_SIZE)
        )
        count = 0
        for job in self.session.scalars(stmt):
            self.matches.upsert(user_id, job.id, self.score(context, job))
            count += 1
        AuditService(self.session).record(
            "matching.recalculated", actor_type=actor_type, actor_id=user_id,
            entity_type="user", entity_id=user_id, details={"jobs": count},
        )  # fmt: skip
        self.session.commit()
        publish_event(EventType.MATCHING_RECALCULATED, {"jobs_matched": count}, user_id)
        logger.info("Matching recalculated", extra={"user_id": str(user_id), "jobs": count})
        return count

    # --- Poids ---

    def get_settings(self, user: User) -> MatchingSettings:
        settings_row = self.settings_repository.get_or_create(user.id)
        self.session.commit()
        return settings_row

    def update_settings(self, user: User, data: MatchingSettingsUpdate) -> MatchingSettings:
        settings_row = self.settings_repository.get_or_create(user.id)
        for field_name, value in data.model_dump(exclude_unset=True, exclude_none=True).items():
            setattr(settings_row, field_name, value)
        self.session.commit()
        return settings_row

    def reset_settings(self, user: User) -> MatchingSettings:
        """Remet les poids aux valeurs du .env."""
        settings_row = self.settings_repository.get_or_create(user.id)
        app_settings = get_settings()
        for name in WEIGHT_FIELDS:
            setattr(
                settings_row,
                f"{name}_weight",
                getattr(app_settings, f"MATCHING_{name.upper()}_WEIGHT"),
            )
        self.session.commit()
        return settings_row

    @staticmethod
    def _weights(settings_row: MatchingSettings) -> MatchingWeights:
        return MatchingWeights(
            **{name: getattr(settings_row, f"{name}_weight") for name in WEIGHT_FIELDS}
        )
