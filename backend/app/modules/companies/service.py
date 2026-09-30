import uuid
from typing import Any

from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, NotFoundError
from app.modules.companies.models import Company
from app.modules.companies.repository import CompanyRepository
from app.modules.companies.schemas import CompanyCreate, CompanyUpdate
from app.shared.enums import DataOrigin
from app.shared.pagination import PaginationParams
from app.shared.utils import normalize_company_name

# Champs qu'une collecte peut renseigner (jamais inventés : uniquement recopiés).
COLLECTABLE_FIELDS = (
    "website", "logo_url", "description", "industry", "employee_count", "address",
    "postal_code", "city", "country", "email", "phone", "linkedin_url", "facebook_url",
    "instagram_url",
)  # fmt: skip


class CompanyService:
    """Gestion des entreprises (saisie manuelle et enrichissement par les collectes)."""

    def __init__(self, session: Session) -> None:
        self.session = session
        self.repository = CompanyRepository(session)

    def list_companies(
        self,
        pagination: PaginationParams,
        search: str | None = None,
        city: str | None = None,
        country: str | None = None,
        industry: str | None = None,
    ) -> tuple[list[Company], int]:
        stmt = self.repository.search_query(search, city, country, industry)
        return self.repository.paginate(stmt, pagination)

    def get(self, company_id: uuid.UUID) -> Company:
        company = self.repository.get(company_id)
        if company is None:
            raise NotFoundError("Company not found", code="COMPANY_NOT_FOUND")
        return company

    def create(self, data: CompanyCreate) -> Company:
        normalized = normalize_company_name(data.name) or data.name.lower()
        if self.repository.get_by_normalized_name(normalized):
            raise ConflictError("A company with this name already exists", code="COMPANY_EXISTS")
        values = data.model_dump(mode="json", exclude_none=True)
        company = self.repository.add(
            Company(normalized_name=normalized, data_source=DataOrigin.MANUAL, **values)
        )
        self.session.commit()
        return company

    def update(self, company_id: uuid.UUID, data: CompanyUpdate) -> Company:
        company = self.get(company_id)
        updates = data.model_dump(mode="json", exclude_unset=True)
        if updates.get("name"):
            normalized = normalize_company_name(updates["name"]) or updates["name"].lower()
            duplicate = self.repository.get_by_normalized_name(normalized)
            if duplicate and duplicate.id != company.id:
                raise ConflictError(
                    "A company with this name already exists", code="COMPANY_EXISTS"
                )
            company.normalized_name = normalized
        for field, value in updates.items():
            setattr(company, field, value)
        # Une valeur corrigée à la main n'a plus de provenance "collecte".
        company.field_sources = {
            key: value for key, value in company.field_sources.items() if key not in updates
        }
        self.session.commit()
        return company

    def delete(self, company_id: uuid.UUID) -> None:
        self.repository.delete(self.get(company_id))
        self.session.commit()

    def find_or_create_from_collect(
        self,
        name: str,
        collected: dict[str, Any],
        *,
        origin: DataOrigin,
        source_id: uuid.UUID | None,
        source_url: str | None,
    ) -> Company:
        """Retrouve l'entreprise par son nom normalisé, ou la crée (sans commit).

        Une donnée existante n'est jamais écrasée : on complète seulement les champs vides,
        en notant la provenance de chaque champ complété.
        """
        normalized = normalize_company_name(name) or name.lower()
        company = self.repository.get_by_normalized_name(normalized)
        provenance = source_url or (f"source:{source_id}" if source_id else origin.value)
        if company is None:
            values = {
                field: collected[field] for field in COLLECTABLE_FIELDS if collected.get(field)
            }
            company = self.repository.add(
                Company(
                    name=name.strip()[:255],
                    normalized_name=normalized,
                    data_source=origin,
                    source_id=source_id,
                    source_url=source_url,
                    field_sources=dict.fromkeys(values, provenance),
                    **values,
                )
            )
            return company

        added_sources = dict(company.field_sources)
        for field in COLLECTABLE_FIELDS:
            value = collected.get(field)
            if value and not getattr(company, field):
                setattr(company, field, value)
                added_sources[field] = provenance
        company.field_sources = added_sources
        return company
