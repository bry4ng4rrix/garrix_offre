import uuid

from sqlalchemy import ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base, TimestampMixin, UUIDPrimaryKeyMixin, enum_column
from app.shared.enums import Priority


class JobTitle(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Poste recherché par l'utilisateur (ex: "Python Developer").

    `enabled=False` garde le poste en mémoire sans l'utiliser dans le matching.
    """

    __tablename__ = "job_titles"
    __table_args__ = (UniqueConstraint("user_id", "normalized_title"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(200))
    normalized_title: Mapped[str] = mapped_column(String(200))
    priority: Mapped[Priority] = mapped_column(enum_column(Priority), default=Priority.MEDIUM)
    enabled: Mapped[bool] = mapped_column(default=True)
