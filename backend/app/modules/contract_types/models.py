from sqlalchemy import String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base, TimestampMixin, UUIDPrimaryKeyMixin


class ContractType(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Type de contrat (CDI, CDD, Freelance...). Référentiel dynamique, géré depuis l'API.

    `aliases` sert à la normalisation des offres : "permanent", "full-time permanent"...
    sont reconnus comme "cdi".
    """

    __tablename__ = "contract_types"

    code: Mapped[str] = mapped_column(String(50), unique=True)
    name: Mapped[str] = mapped_column(String(100))
    description: Mapped[str | None] = mapped_column(Text)
    aliases: Mapped[list[str]] = mapped_column(default=list)
    is_active: Mapped[bool] = mapped_column(default=True)
    sort_order: Mapped[int] = mapped_column(default=0)
