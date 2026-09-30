import uuid

from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError, ConflictError, NotFoundError
from app.modules.profile.repository import ProfileRepository
from app.modules.skills.models import ProfileSkill, Skill, SkillCategory
from app.modules.skills.repository import (
    ProfileSkillRepository,
    SkillCategoryRepository,
    SkillRepository,
)
from app.modules.skills.schemas import (
    CatalogSkillUpdate,
    ProfileSkillCreate,
    ProfileSkillUpdate,
    SkillCategoryCreate,
    SkillCategoryUpdate,
)
from app.modules.users.models import User
from app.shared.pagination import PaginationParams
from app.shared.utils import normalize_text


class SkillCatalogService:
    """Catalogue global des compétences et de leurs catégories.

    Le catalogue est partagé : une compétence ajoutée à un profil y est créée
    automatiquement, et sert ensuite à reconnaître cette compétence dans les offres.
    """

    def __init__(self, session: Session) -> None:
        self.session = session
        self.skills = SkillRepository(session)
        self.categories = SkillCategoryRepository(session)

    # --- Compétences ---

    def get_or_create(self, name: str, category_code: str | None = None) -> Skill:
        normalized = normalize_text(name)
        if not normalized:
            raise BusinessRuleError("Invalid skill name", code="INVALID_SKILL_NAME")
        skill = self.skills.get_by_normalized_name(normalized)
        if skill is None:
            category = self._category_or_none(category_code)
            skill = self.skills.add(
                Skill(name=name.strip(), normalized_name=normalized, category=category)
            )
        elif category_code and skill.category is None:
            skill.category = self._category_or_none(category_code)
        return skill

    def search(
        self, pagination: PaginationParams, search: str | None, category: str | None
    ) -> tuple[list[Skill], int]:
        return self.skills.paginate(self.skills.search_query(search, category), pagination)

    def update_catalog_skill(self, skill_id: uuid.UUID, data: CatalogSkillUpdate) -> Skill:
        skill = self.skills.get(skill_id)
        if skill is None:
            raise NotFoundError("Skill not found", code="SKILL_NOT_FOUND")
        updates = data.model_dump(exclude_unset=True)
        if "category" in updates:
            skill.category = self._category_or_none(updates["category"])
        if updates.get("aliases") is not None:
            skill.aliases = updates["aliases"]
        self.session.commit()
        return skill

    # --- Catégories ---

    def list_categories(self) -> list[SkillCategory]:
        return self.categories.list_categories()

    def create_category(self, data: SkillCategoryCreate) -> SkillCategory:
        if self.categories.get_by_code(data.code):
            raise ConflictError("This category already exists", code="SKILL_CATEGORY_EXISTS")
        category = self.categories.add(SkillCategory(**data.model_dump()))
        self.session.commit()
        return category

    def update_category(self, category_id: uuid.UUID, data: SkillCategoryUpdate) -> SkillCategory:
        category = self._get_category(category_id)
        for field, value in data.model_dump(exclude_unset=True).items():
            setattr(category, field, value)
        self.session.commit()
        return category

    def delete_category(self, category_id: uuid.UUID) -> None:
        self.categories.delete(self._get_category(category_id))
        self.session.commit()

    def _get_category(self, category_id: uuid.UUID) -> SkillCategory:
        category = self.categories.get(category_id)
        if category is None:
            raise NotFoundError("Skill category not found", code="SKILL_CATEGORY_NOT_FOUND")
        return category

    def _category_or_none(self, code: str | None) -> SkillCategory | None:
        if not code:
            return None
        category = self.categories.get_by_code(code.strip().lower())
        if category is None:
            raise BusinessRuleError(
                "Unknown skill category", code="UNKNOWN_SKILL_CATEGORY", details={"category": code}
            )
        return category


class SkillService:
    """Compétences du profil de l'utilisateur connecté (/api/v1/skills)."""

    def __init__(self, session: Session) -> None:
        self.session = session
        self.catalog = SkillCatalogService(session)
        self.profile_skills = ProfileSkillRepository(session)
        self.profiles = ProfileRepository(session)

    def list_skills(self, user: User, enabled_only: bool = False) -> list[ProfileSkill]:
        profile = self.profiles.get_by_user(user.id)
        if profile is None:
            return []
        return self.profile_skills.list_for_profile(profile.id, enabled_only)

    def get_skill(self, user: User, profile_skill_id: uuid.UUID) -> ProfileSkill:
        profile = self.profiles.get_by_user(user.id)
        profile_skill = (
            self.profile_skills.get_for_profile(profile_skill_id, profile.id) if profile else None
        )
        if profile_skill is None:
            raise NotFoundError("Skill not found", code="SKILL_NOT_FOUND")
        return profile_skill

    def add_skill(self, user: User, data: ProfileSkillCreate) -> ProfileSkill:
        profile = self.profiles.get_or_create(user.id, user.email)
        skill = self.catalog.get_or_create(data.name, data.category)
        if self.profile_skills.get_by_skill(profile.id, skill.id):
            raise ConflictError("This skill is already in your profile", code="SKILL_ALREADY_ADDED")
        profile_skill = self.profile_skills.add(
            ProfileSkill(
                profile_id=profile.id,
                skill=skill,
                level=data.level,
                years_experience=data.years_experience,
                priority=data.priority,
                enabled=data.enabled,
            )
        )
        self.session.commit()
        return profile_skill

    def update_skill(
        self, user: User, profile_skill_id: uuid.UUID, data: ProfileSkillUpdate
    ) -> ProfileSkill:
        profile_skill = self.get_skill(user, profile_skill_id)
        updates = data.model_dump(exclude_unset=True)
        category = updates.pop("category", None)
        if category:
            self.catalog.get_or_create(profile_skill.skill.name, category)
        for field, value in updates.items():
            setattr(profile_skill, field, value)
        self.session.commit()
        return profile_skill

    def delete_skill(self, user: User, profile_skill_id: uuid.UUID) -> None:
        self.profile_skills.delete(self.get_skill(user, profile_skill_id))
        self.session.commit()
