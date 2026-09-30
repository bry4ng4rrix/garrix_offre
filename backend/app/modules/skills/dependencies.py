from app.api.dependencies import DbSession
from app.modules.skills.service import SkillCatalogService, SkillService


def get_skill_service(session: DbSession) -> SkillService:
    return SkillService(session)


def get_skill_catalog_service(session: DbSession) -> SkillCatalogService:
    return SkillCatalogService(session)
