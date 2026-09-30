from app.api.dependencies import DbSession
from app.modules.contract_types.service import ContractTypeService


def get_contract_type_service(session: DbSession) -> ContractTypeService:
    return ContractTypeService(session)
