import uuid

from sqlalchemy import Select, or_, select

from app.modules.skills.models import ProfileSkill, Skill, SkillCategory
from app.shared.repository import BaseRepository


class SkillCategoryRepository(BaseRepository[SkillCategory]):
    model = SkillCategory

    def get_by_code(self, code: str) -> SkillCategory | None:
        return self.session.scalar(select(SkillCategory).where(SkillCategory.code == code))

    def list_categories(self) -> list[SkillCategory]:
        return list(self.session.scalars(select(SkillCategory).order_by(SkillCategory.name)))


class SkillRepository(BaseRepository[Skill]):
    model = Skill

    def get_by_normalized_name(self, normalized_name: str) -> Skill | None:
        return self.session.scalar(select(Skill).where(Skill.normalized_name == normalized_name))

    def get_by_normalized_names(self, normalized_names: list[str]) -> list[Skill]:
        if not normalized_names:
            return []
        return list(
            self.session.scalars(select(Skill).where(Skill.normalized_name.in_(normalized_names)))
        )

    def search_query(self, search: str | None, category_code: str | None) -> Select[tuple[Skill]]:
        stmt = select(Skill).outerjoin(Skill.category).order_by(Skill.name)
        if search:
            pattern = f"%{search.lower()}%"
            stmt = stmt.where(or_(Skill.normalized_name.like(pattern), Skill.name.ilike(pattern)))
        if category_code:
            stmt = stmt.where(SkillCategory.code == category_code)
        return stmt

    def list_all_skills(self) -> list[Skill]:
        return list(self.session.scalars(select(Skill)))


class ProfileSkillRepository(BaseRepository[ProfileSkill]):
    model = ProfileSkill

    def list_for_profile(
        self, profile_id: uuid.UUID, enabled_only: bool = False
    ) -> list[ProfileSkill]:
        stmt = (
            select(ProfileSkill)
            .join(ProfileSkill.skill)
            .where(ProfileSkill.profile_id == profile_id)
            .order_by(Skill.name)
        )
        if enabled_only:
            stmt = stmt.where(ProfileSkill.enabled.is_(True))
        return list(self.session.scalars(stmt).unique())

    def get_for_profile(
        self, profile_skill_id: uuid.UUID, profile_id: uuid.UUID
    ) -> ProfileSkill | None:
        return self.session.scalar(
            select(ProfileSkill).where(
                ProfileSkill.id == profile_skill_id, ProfileSkill.profile_id == profile_id
            )
        )

    def get_by_skill(self, profile_id: uuid.UUID, skill_id: uuid.UUID) -> ProfileSkill | None:
        return self.session.scalar(
            select(ProfileSkill).where(
                ProfileSkill.profile_id == profile_id, ProfileSkill.skill_id == skill_id
            )
        )
