import hashlib
import logging
import uuid
from collections.abc import Iterator
from typing import BinaryIO

from fastapi import UploadFile
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.exceptions import NotFoundError, PayloadTooLargeError
from app.modules.audit.service import AuditService
from app.modules.documents.models import Document
from app.modules.documents.repository import DocumentRepository
from app.modules.documents.schemas import DocumentUpdate
from app.modules.documents.storage import StorageService, get_storage
from app.modules.documents.validation import HEADER_SIZE, validate_upload
from app.modules.users.models import User
from app.shared.enums import ActorType, DocumentType
from app.shared.pagination import PaginationParams
from app.shared.utils import normalize_text

logger = logging.getLogger("app.documents")


class _LimitedHashingReader:
    """Lit un flux en calculant son SHA-256 et en refusant de dépasser `max_size` octets."""

    def __init__(self, stream: BinaryIO, max_size: int) -> None:
        self.stream = stream
        self.max_size = max_size
        self.size = 0
        self.hasher = hashlib.sha256()

    def read(self, size: int = -1) -> bytes:
        chunk = self.stream.read(size)
        self.size += len(chunk)
        if self.size > self.max_size:
            raise PayloadTooLargeError(
                f"File is too large (max {self.max_size // (1024 * 1024)} MB)",
                code="FILE_TOO_LARGE",
            )
        self.hasher.update(chunk)
        return chunk


class DocumentService:
    """Gestion des documents privés : CV, lettres de motivation, photos (RG-11)."""

    def __init__(self, session: Session, storage: StorageService | None = None) -> None:
        self.session = session
        self.documents = DocumentRepository(session)
        self.storage = storage or get_storage()
        self.audit = AuditService(session)

    def upload(
        self,
        user: User,
        file: UploadFile,
        document_type: DocumentType,
        *,
        title: str | None = None,
        language: str | None = None,
        target_job_title: str | None = None,
        is_primary: bool = False,
    ) -> Document:
        header = file.file.read(HEADER_SIZE)
        file.file.seek(0)
        validated = validate_upload(file.filename, file.content_type, header, document_type)

        storage_key = f"{user.id}/{uuid.uuid4().hex}.{validated.extension}"
        reader = _LimitedHashingReader(file.file, get_settings().max_upload_size_bytes)
        try:
            self.storage.save(storage_key, reader)  # type: ignore[arg-type]
        except Exception:
            self.storage.delete(storage_key)
            raise

        # Le premier document d'un type devient automatiquement le principal.
        make_primary = is_primary or self.documents.count_of_type(user.id, document_type) == 0
        if make_primary:
            self.documents.unset_primary(user.id, document_type)
        document = self.documents.add(
            Document(
                user_id=user.id,
                document_type=document_type,
                title=(title or validated.safe_filename)[:200],
                original_filename=validated.safe_filename,
                storage_key=storage_key,
                mime_type=validated.mime_type,
                extension=validated.extension,
                size_bytes=reader.size,
                checksum_sha256=reader.hasher.hexdigest(),
                language=language,
                target_job_title=target_job_title,
                is_primary=make_primary,
            )
        )
        self.audit.record(
            "document.uploaded", actor_type=ActorType.USER, actor_id=user.id,
            entity_type="document", entity_id=document.id,
            details={"type": document_type.value, "size": reader.size},
        )  # fmt: skip
        self.session.commit()
        return document

    def list_documents(
        self,
        user: User,
        pagination: PaginationParams,
        document_type: DocumentType | None = None,
        is_active: bool | None = None,
        language: str | None = None,
    ) -> tuple[list[Document], int]:
        stmt = self.documents.list_query(user.id, document_type, is_active, language)
        return self.documents.paginate(stmt, pagination)

    def get(self, user: User, document_id: uuid.UUID) -> Document:
        document = self.documents.get_for_user(document_id, user.id)
        if document is None:
            # 404 même si le document existe chez un autre utilisateur : on ne révèle rien.
            raise NotFoundError("Document not found", code="DOCUMENT_NOT_FOUND")
        return document

    def update(self, user: User, document_id: uuid.UUID, data: DocumentUpdate) -> Document:
        document = self.get(user, document_id)
        updates = data.model_dump(exclude_unset=True)
        if updates.get("is_primary"):
            self.documents.unset_primary(user.id, document.document_type)
        for field, value in updates.items():
            setattr(document, field, value)
        self.session.commit()
        return document

    def delete(self, user: User, document_id: uuid.UUID) -> None:
        document = self.get(user, document_id)
        storage_key = document.storage_key
        self.documents.delete(document)
        self.audit.record(
            "document.deleted", actor_type=ActorType.USER, actor_id=user.id,
            entity_type="document", entity_id=document_id,
        )  # fmt: skip
        self.session.commit()
        self.storage.delete(storage_key)

    def stream(self, user: User, document_id: uuid.UUID) -> tuple[Document, Iterator[bytes]]:
        document = self.get(user, document_id)
        if not self.storage.exists(document.storage_key):
            logger.error("Stored file missing", extra={"document_id": str(document.id)})
            raise NotFoundError("File not found in storage", code="DOCUMENT_FILE_MISSING")
        return document, self.storage.iter_chunks(document.storage_key)

    def read_content(self, document: Document) -> bytes:
        return self.storage.read_bytes(document.storage_key)

    def choose_cv(
        self, user: User, language: str | None = None, job_title: str | None = None
    ) -> Document | None:
        """Choisit le CV le plus adapté : même langue, poste proche, puis CV principal."""
        target_words = set(normalize_text(job_title).split())

        def score(cv: Document) -> int:
            points = 0
            if language and cv.language == language:
                points += 4
            if target_words and cv.target_job_title:
                points += 2 * len(target_words & set(normalize_text(cv.target_job_title).split()))
            if cv.is_primary:
                points += 1
            return points

        cvs = self.documents.list_active_cvs(user.id)
        return max(cvs, key=score) if cvs else None
