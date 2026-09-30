import uuid

from sqlalchemy import BigInteger, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base, TimestampMixin, UUIDPrimaryKeyMixin, enum_column
from app.shared.enums import DocumentType


class Document(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Fichier privé d'un utilisateur : CV, lettre de motivation, photo, autre.

    Le fichier lui-même est dans le StorageService (clé `storage_key`), jamais exposé
    publiquement : on le télécharge via GET /documents/{id}/download (authentifié).
    """

    __tablename__ = "documents"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    document_type: Mapped[DocumentType] = mapped_column(enum_column(DocumentType))
    title: Mapped[str] = mapped_column(String(200))
    original_filename: Mapped[str] = mapped_column(String(255))
    storage_key: Mapped[str] = mapped_column(String(500), unique=True)
    mime_type: Mapped[str] = mapped_column(String(100))
    extension: Mapped[str] = mapped_column(String(10))
    size_bytes: Mapped[int] = mapped_column(BigInteger)
    checksum_sha256: Mapped[str] = mapped_column(String(64))
    language: Mapped[str | None] = mapped_column(String(3))
    target_job_title: Mapped[str | None] = mapped_column(String(200))
    is_active: Mapped[bool] = mapped_column(default=True)
    is_primary: Mapped[bool] = mapped_column(default=False)
