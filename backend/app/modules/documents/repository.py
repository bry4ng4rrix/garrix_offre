import uuid

from sqlalchemy import Select, func, select, update

from app.modules.documents.models import Document
from app.shared.enums import DocumentType
from app.shared.repository import BaseRepository


class DocumentRepository(BaseRepository[Document]):
    model = Document

    def get_for_user(self, document_id: uuid.UUID, user_id: uuid.UUID) -> Document | None:
        return self.session.scalar(
            select(Document).where(Document.id == document_id, Document.user_id == user_id)
        )

    def list_query(
        self,
        user_id: uuid.UUID,
        document_type: DocumentType | None = None,
        is_active: bool | None = None,
        language: str | None = None,
    ) -> Select[tuple[Document]]:
        stmt = (
            select(Document)
            .where(Document.user_id == user_id)
            .order_by(Document.is_primary.desc(), Document.created_at.desc())
        )
        if document_type:
            stmt = stmt.where(Document.document_type == document_type)
        if is_active is not None:
            stmt = stmt.where(Document.is_active.is_(is_active))
        if language:
            stmt = stmt.where(Document.language == language)
        return stmt

    def list_active_cvs(self, user_id: uuid.UUID) -> list[Document]:
        stmt = self.list_query(user_id, DocumentType.CV, is_active=True)
        return list(self.session.scalars(stmt))

    def count_of_type(self, user_id: uuid.UUID, document_type: DocumentType) -> int:
        stmt = select(func.count()).where(
            Document.user_id == user_id, Document.document_type == document_type
        )
        return self.session.scalar(stmt) or 0

    def unset_primary(self, user_id: uuid.UUID, document_type: DocumentType) -> None:
        self.session.execute(
            update(Document)
            .where(Document.user_id == user_id, Document.document_type == document_type)
            .values(is_primary=False)
        )
