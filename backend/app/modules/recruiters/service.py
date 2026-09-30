import uuid
from typing import Any

from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError, NotFoundError
from app.modules.companies.repository import CompanyRepository
from app.modules.recruiters.models import Recruiter
from app.modules.recruiters.repository import RecruiterRepository
from app.modules.recruiters.schemas import (
    RecruiterCreate,
    RecruiterUpdate,
    check_contact_provenance,
)
from app.shared.enums import ContactSource
from app.shared.pagination import PaginationParams

CONTACT_FIELDS = (
    "first_name",
    "last_name",
    "job_title",
    "email",
    "phone",
    "linkedin_url",
    "website",
)


class RecruiterService:
    """Gestion des recruteurs et de leurs coordonnées publiques (RG-07)."""

    def __init__(self, session: Session) -> None:
        self.session = session
        self.repository = RecruiterRepository(session)

    def list_recruiters(
        self,
        pagination: PaginationParams,
        search: str | None = None,
        company_id: uuid.UUID | None = None,
    ) -> tuple[list[Recruiter], int]:
        return self.repository.paginate(
            self.repository.search_query(search, company_id), pagination
        )

    def get(self, recruiter_id: uuid.UUID) -> Recruiter:
        recruiter = self.repository.get(recruiter_id)
        if recruiter is None:
            raise NotFoundError("Recruiter not found", code="RECRUITER_NOT_FOUND")
        return recruiter

    def create(self, data: RecruiterCreate) -> Recruiter:
        self._check_company(data.company_id)
        values = data.model_dump(mode="json", exclude_none=True)
        if values.get("company_id"):
            values["company_id"] = uuid.UUID(values["company_id"])
        recruiter = self.repository.add(Recruiter(**values))
        self.session.commit()
        return recruiter

    def update(self, recruiter_id: uuid.UUID, data: RecruiterUpdate) -> Recruiter:
        recruiter = self.get(recruiter_id)
        updates = data.model_dump(mode="json", exclude_unset=True)
        if "company_id" in updates:
            self._check_company(data.company_id)
            updates["company_id"] = data.company_id
        for field, value in updates.items():
            setattr(recruiter, field, value)
        try:
            check_contact_provenance(
                recruiter.email, recruiter.phone, recruiter.contact_source, recruiter.source_url
            )
        except ValueError as exc:
            self.session.rollback()
            raise BusinessRuleError(str(exc), code="CONTACT_PROVENANCE_REQUIRED") from exc
        self.session.commit()
        return recruiter

    def delete(self, recruiter_id: uuid.UUID) -> None:
        self.repository.delete(self.get(recruiter_id))
        self.session.commit()

    def find_or_create_from_collect(
        self,
        collected: dict[str, Any],
        *,
        company_id: uuid.UUID | None,
        source_id: uuid.UUID | None,
        default_source_url: str | None,
    ) -> Recruiter | None:
        """Retrouve (par email, puis nom + entreprise) ou crée un recruteur collecté. Sans commit.

        Seules les valeurs présentes dans l'offre sont enregistrées ; rien n'est déduit.
        """
        email = (collected.get("email") or "").strip().lower() or None
        name = (collected.get("name") or "").strip() or None
        if not (email or name or collected.get("first_name") or collected.get("last_name")):
            return None

        recruiter = self.repository.get_by_email(email) if email else None
        if recruiter is None and name:
            recruiter = self.repository.get_by_name_and_company(name, company_id)

        contact_source = collected.get("contact_source") or ContactSource.JOB_LISTING.value
        source_url = collected.get("source_url") or default_source_url
        if recruiter is None:
            recruiter = self.repository.add(
                Recruiter(
                    name=name,
                    company_id=company_id,
                    contact_source=contact_source,
                    source_url=source_url,
                    source_id=source_id,
                    **{field: collected.get(field) for field in CONTACT_FIELDS if field != "email"},
                    email=email,
                )
            )
            return recruiter

        # Complète uniquement les champs vides.
        for field in CONTACT_FIELDS:
            value = email if field == "email" else collected.get(field)
            if value and not getattr(recruiter, field):
                setattr(recruiter, field, value)
        if recruiter.company_id is None and company_id:
            recruiter.company_id = company_id
        return recruiter

    def _check_company(self, company_id: uuid.UUID | None) -> None:
        if company_id and CompanyRepository(self.session).get(company_id) is None:
            raise BusinessRuleError("Unknown company", code="COMPANY_NOT_FOUND")
