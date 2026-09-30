from app.api.dependencies import DbSession
from app.modules.documents.service import DocumentService


def get_document_service(session: DbSession) -> DocumentService:
    return DocumentService(session)
