import uuid
from typing import Any

from sqlalchemy import Column, ForeignKey, String, Table
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.config import get_settings
from app.core.database import Base, TimestampMixin, UUIDPrimaryKeyMixin, enum_column
from app.modules.contract_types.models import ContractType
from app.shared.enums import SalaryPeriod

# Association N:M entre préférences et types de contrat (UML 06).
preference_contract_types = Table(
    "preference_contract_types",
    Base.metadata,
    Column(
        "preference_id",
        ForeignKey("search_preferences.id", ondelete="CASCADE"),
        primary_key=True,
    ),
    Column(
        "contract_type_id",
        ForeignKey("contract_types.id", ondelete="CASCADE"),
        primary_key=True,
    ),
)


def _default_threshold() -> int:
    return get_settings().MATCHING_DEFAULT_THRESHOLD


class SearchPreference(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Préférences de recherche de l'utilisateur (1:1 avec User).

    Les postes recherchés (job_titles) et les technologies recherchées
    (experience_preferences) ont leurs propres tables ; GET /preferences les agrège.
    """

    __tablename__ = "search_preferences"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True
    )
    remote: Mapped[bool] = mapped_column(default=True)
    hybrid: Mapped[bool] = mapped_column(default=True)
    onsite: Mapped[bool] = mapped_column(default=True)
    # [{"city": "Paris", "country": "France"}, {"city": null, "country": "Madagascar"}]
    locations: Mapped[list[dict[str, Any]]] = mapped_column(default=list)
    experience_levels: Mapped[list[str]] = mapped_column(default=list)
    languages: Mapped[list[str]] = mapped_column(default=list)
    minimum_salary: Mapped[int | None]
    currency: Mapped[str] = mapped_column(String(3), default="EUR")
    salary_period: Mapped[SalaryPeriod] = mapped_column(
        enum_column(SalaryPeriod), default=SalaryPeriod.MONTH
    )
    # Score à partir duquel une offre est "très compatible" (notification high_match).
    matching_threshold: Mapped[int] = mapped_column(default=_default_threshold)

    contract_types: Mapped[list[ContractType]] = relationship(
        secondary=preference_contract_types, lazy="selectin", order_by=ContractType.sort_order
    )

    @property
    def contract_type_codes(self) -> list[str]:
        return [contract_type.code for contract_type in self.contract_types]
