import uuid

from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError, ConflictError, NotFoundError
from app.modules.contract_types.models import ContractType
from app.modules.contract_types.repository import ContractTypeRepository
from app.modules.contract_types.schemas import ContractTypeCreate, ContractTypeUpdate
from app.shared.utils import normalize_text


class ContractTypeService:
    """Gestion du référentiel des types de contrat (lecture pour tous, écriture admin)."""

    def __init__(self, session: Session) -> None:
        self.session = session
        self.repository = ContractTypeRepository(session)

    def list_types(self, include_inactive: bool = False) -> list[ContractType]:
        return self.repository.list_types(include_inactive)

    def get(self, contract_type_id: uuid.UUID) -> ContractType:
        contract_type = self.repository.get(contract_type_id)
        if contract_type is None:
            raise NotFoundError("Contract type not found", code="CONTRACT_TYPE_NOT_FOUND")
        return contract_type

    def create(self, data: ContractTypeCreate) -> ContractType:
        code = data.resolved_code()
        if self.repository.get_by_code(code):
            raise ConflictError("This contract type already exists", code="CONTRACT_TYPE_EXISTS")
        contract_type = self.repository.add(
            ContractType(
                code=code,
                name=data.name.strip(),
                description=data.description,
                aliases=data.aliases,
                is_active=data.is_active,
                sort_order=data.sort_order,
            )
        )
        self.session.commit()
        return contract_type

    def update(self, contract_type_id: uuid.UUID, data: ContractTypeUpdate) -> ContractType:
        contract_type = self.get(contract_type_id)
        for field, value in data.model_dump(exclude_unset=True).items():
            setattr(contract_type, field, value)
        self.session.commit()
        return contract_type

    def delete(self, contract_type_id: uuid.UUID) -> None:
        self.repository.delete(self.get(contract_type_id))
        self.session.commit()

    def resolve_codes(self, codes: list[str]) -> list[ContractType]:
        """Transforme une liste de codes en objets ; erreur 422 si un code est inconnu."""
        wanted = {code.strip().lower() for code in codes if code.strip()}
        found = self.repository.get_by_codes(sorted(wanted))
        missing = wanted - {contract_type.code for contract_type in found}
        if missing:
            raise BusinessRuleError(
                "Unknown contract type(s)",
                code="UNKNOWN_CONTRACT_TYPE",
                details={"codes": sorted(missing)},
            )
        return found


def match_contract_type(text: str | None, contract_types: list[ContractType]) -> str | None:
    """Retrouve le code d'un type de contrat à partir d'un texte libre ("Full Time", "CDI"...).

    Les alias les plus longs sont testés en premier ("full time permanent" avant "full time").
    """
    normalized = normalize_text(text)
    if not normalized:
        return None
    candidates: list[tuple[str, str]] = []
    for contract_type in contract_types:
        for alias in {
            contract_type.code.replace("_", " "),
            normalize_text(contract_type.name),
            *contract_type.aliases,
        }:
            if alias:
                candidates.append((alias, contract_type.code))
    candidates.sort(key=lambda item: len(item[0]), reverse=True)
    padded = f" {normalized} "
    for alias, code in candidates:
        if f" {alias} " in padded:
            return code
    return None
