from app.api.dependencies import DbSession
from app.modules.companies.service import CompanyService


def get_company_service(session: DbSession) -> CompanyService:
    return CompanyService(session)
