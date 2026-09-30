import uuid
from collections import defaultdict

from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError, ConflictError, NotFoundError
from app.modules.experiences.models import Experience, ExperienceLevel, ExperiencePreference
from app.modules.experiences.repository import (
    ExperienceLevelRepository,
    ExperiencePreferenceRepository,
    ExperienceRepository,
)
from app.modules.experiences.schemas import (
    ExperienceCreate,
    ExperienceLevelCreate,
    ExperienceLevelUpdate,
    ExperiencePreferenceCreate,
    ExperiencePreferenceUpdate,
    ExperienceUpdate,
)
from app.modules.profile.repository import ProfileRepository
from app.modules.skills.service import SkillCatalogService
from app.modules.users.models import User
from app.shared.utils import normalize_text


class ExperienceLevelService:
    """Référentiel des niveaux d'expérience (lecture pour tous, écriture admin)."""

    def __init__(self, session: Session) -> None:
        self.session = session
        self.repository = ExperienceLevelRepository(session)

    def list_levels(self) -> list[ExperienceLevel]:
        return self.repository.list_levels()

    def get(self, level_id: uuid.UUID) -> ExperienceLevel:
        level = self.repository.get(level_id)
        if level is None:
            raise NotFoundError("Experience level not found", code="EXPERIENCE_LEVEL_NOT_FOUND")
        return level

    def create(self, data: ExperienceLevelCreate) -> ExperienceLevel:
        if self.repository.get_by_code(data.code):
            raise ConflictError("This level already exists", code="EXPERIENCE_LEVEL_EXISTS")
        level = self.repository.add(ExperienceLevel(**data.model_dump()))
        self.session.commit()
        return level

    def update(self, level_id: uuid.UUID, data: ExperienceLevelUpdate) -> ExperienceLevel:
        level = self.get(level_id)
        for field, value in data.model_dump(exclude_unset=True).items():
            setattr(level, field, value)
        self.session.commit()
        return level

    def delete(self, level_id: uuid.UUID) -> None:
        self.repository.delete(self.get(level_id))
        self.session.commit()

    def ensure_codes_exist(self, codes: list[str]) -> list[str]:
        """Vérifie des codes de niveau (erreur 422 si inconnus) et les retourne normalisés."""
        known = self.repository.ranks_by_code()
        cleaned = sorted({code.strip().lower() for code in codes if code.strip()})
        unknown = [code for code in cleaned if code not in known]
        if unknown:
            raise BusinessRuleError(
                "Unknown experience level(s)",
                code="UNKNOWN_EXPERIENCE_LEVEL",
                details={"codes": unknown},
            )
        return cleaned


def match_experience_level(text: str | None, levels: list[ExperienceLevel]) -> str | None:
    """Retrouve un code de niveau dans un texte libre ("Senior Python Developer" -> "senior")."""
    padded = f" {normalize_text(text)} "
    if not padded.strip():
        return None
    candidates = [
        (alias, level.code)
        for level in levels
        for alias in {level.code, normalize_text(level.name), *level.aliases}
        if alias
    ]
    candidates.sort(key=lambda item: len(item[0]), reverse=True)
    for alias, code in candidates:
        if f" {alias} " in padded:
            return code
    return None


def level_for_years(years: int | None, levels: list[ExperienceLevel]) -> str | None:
    """Niveau correspondant à un nombre d'années (le plus haut dont min_years est atteint)."""
    if years is None:
        return None
    eligible = [level for level in levels if level.min_years <= years]
    return max(eligible, key=lambda level: level.rank).code if eligible else None


class ExperienceService:
    """Parcours professionnel du profil (/api/v1/experiences)."""

    def __init__(self, session: Session) -> None:
        self.session = session
        self.experiences = ExperienceRepository(session)
        self.profiles = ProfileRepository(session)

    def list_experiences(self, user: User) -> list[Experience]:
        profile = self.profiles.get_by_user(user.id)
        return self.experiences.list_for_profile(profile.id) if profile else []

    def get(self, user: User, experience_id: uuid.UUID) -> Experience:
        profile = self.profiles.get_by_user(user.id)
        experience = (
            self.experiences.get_for_profile(experience_id, profile.id) if profile else None
        )
        if experience is None:
            raise NotFoundError("Experience not found", code="EXPERIENCE_NOT_FOUND")
        return experience

    def create(self, user: User, data: ExperienceCreate) -> Experience:
        profile = self.profiles.get_or_create(user.id, user.email)
        experience = self.experiences.add(Experience(profile_id=profile.id, **data.model_dump()))
        self.session.commit()
        return experience

    def update(self, user: User, experience_id: uuid.UUID, data: ExperienceUpdate) -> Experience:
        experience = self.get(user, experience_id)
        for field, value in data.model_dump().items():
            setattr(experience, field, value)
        self.session.commit()
        return experience

    def delete(self, user: User, experience_id: uuid.UUID) -> None:
        self.experiences.delete(self.get(user, experience_id))
        self.session.commit()


class ExperiencePreferenceService:
    """Technologies et expériences recherchées (/api/v1/experience-preferences)."""

    def __init__(self, session: Session) -> None:
        self.session = session
        self.preferences = ExperiencePreferenceRepository(session)
        self.catalog = SkillCatalogService(session)

    def list_preferences(
        self, user: User, enabled_only: bool = False
    ) -> list[ExperiencePreference]:
        return self.preferences.list_for_user(user.id, enabled_only)

    def grouped_by_category(self, user: User) -> dict[str, list[ExperiencePreference]]:
        """Ex : {"frontend": [React, Next.js], "backend": [Python, Django], "other": [...]}."""
        groups: dict[str, list[ExperiencePreference]] = defaultdict(list)
        for preference in self.list_preferences(user):
            groups[preference.category_code or "other"].append(preference)
        return dict(groups)

    def get(self, user: User, preference_id: uuid.UUID) -> ExperiencePreference:
        preference = self.preferences.get_for_user(preference_id, user.id)
        if preference is None:
            raise NotFoundError(
                "Experience preference not found", code="EXPERIENCE_PREFERENCE_NOT_FOUND"
            )
        return preference

    def create(self, user: User, data: ExperiencePreferenceCreate) -> ExperiencePreference:
        skill = self.catalog.get_or_create(data.technology, data.category)
        if self.preferences.get_by_skill(user.id, skill.id):
            raise ConflictError(
                "This technology is already in your preferences",
                code="EXPERIENCE_PREFERENCE_EXISTS",
            )
        preference = self.preferences.add(
            ExperiencePreference(
                user_id=user.id,
                skill=skill,
                level=data.level,
                priority=data.priority,
                min_years=data.min_years,
                is_required=data.is_required,
                enabled=data.enabled,
            )
        )
        self.session.commit()
        return preference

    def update(
        self, user: User, preference_id: uuid.UUID, data: ExperiencePreferenceUpdate
    ) -> ExperiencePreference:
        preference = self.get(user, preference_id)
        for field, value in data.model_dump(exclude_unset=True).items():
            setattr(preference, field, value)
        self.session.commit()
        return preference

    def delete(self, user: User, preference_id: uuid.UUID) -> None:
        self.preferences.delete(self.get(user, preference_id))
        self.session.commit()

    def sync_technologies(self, user: User, technologies: list[str]) -> None:
        """Utilisé par PUT /preferences : active les technologies listées, désactive les autres.

        Rien n'est supprimé : niveau, priorité et "obligatoire" sont conservés. Pas de commit.
        """
        wanted: dict[str, str] = {}
        for name in technologies:
            if normalize_text(name):
                wanted.setdefault(normalize_text(name), name.strip())
        existing = {
            pref.skill.normalized_name: pref for pref in self.preferences.list_for_user(user.id)
        }
        for normalized, preference in existing.items():
            preference.enabled = normalized in wanted
        for normalized, name in wanted.items():
            if normalized not in existing:
                skill = self.catalog.get_or_create(name)
                self.preferences.add(ExperiencePreference(user_id=user.id, skill=skill))
