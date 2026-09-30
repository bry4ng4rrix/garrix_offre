from sqlalchemy import select

from app.modules.contract_types.models import ContractType
from app.shared.repository import BaseRepository


class ContractTypeRepository(BaseRepository[ContractType]):
    model = ContractType

    def get_by_code(self, code: str) -> ContractType | None:
        return self.session.scalar(select(ContractType).where(ContractType.code == code))

    def get_by_codes(self, codes: list[str]) -> list[ContractType]:
        if not codes:
            return []
        return list(self.session.scalars(select(ContractType).where(ContractType.code.in_(codes))))

    def list_types(self, include_inactive: bool = False) -> list[ContractType]:
        stmt = select(ContractType).order_by(ContractType.sort_order, ContractType.name)
        if not include_inactive:
            stmt = stmt.where(ContractType.is_active.is_(True))
        return list(self.session.scalars(stmt))
