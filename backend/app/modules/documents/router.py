import uuid
from collections.abc import Iterator
from typing import Annotated
from urllib.parse import quote

from fastapi import APIRouter, Depends, File, Form, Query, UploadFile, status
from fastapi.responses import StreamingResponse

from app.api.dependencies import CurrentUser
from app.modules.documents.dependencies import get_document_service
from app.modules.documents.models import Document
from app.modules.documents.schemas import DocumentRead, DocumentUpdate
from app.modules.documents.service import DocumentService
from app.shared.enums import DocumentType
from app.shared.pagination import Page, PaginationParams, build_page
from app.shared.schemas import ApiResponse, error_responses, ok

router = APIRouter(prefix="/documents", tags=["Documents"])

Service = Annotated[DocumentService, Depends(get_document_service)]


def file_response(
    document: Document, chunks: Iterator[bytes], inline: bool = False
) -> StreamingResponse:
    """Réponse de téléchargement sécurisée (nom de fichier encodé, pas de "sniffing" MIME)."""
    disposition = "inline" if inline else "attachment"
    headers = {
        "Content-Disposition": f"{disposition}; filename*=UTF-8''{quote(document.original_filename)}",
        "Content-Length": str(document.size_bytes),
        "X-Content-Type-Options": "nosniff",
        "Cache-Control": "private, no-store",
    }
    return StreamingResponse(chunks, media_type=document.mime_type, headers=headers)


@router.get(
    "",
    response_model=ApiResponse[Page[DocumentRead]],
    summary="Mes documents",
    responses=error_responses(401),
)
def list_documents(
    user: CurrentUser,
    service: Service,
    pagination: PaginationParams = Depends(),
    document_type: DocumentType | None = None,
    is_active: bool | None = None,
    language: str | None = Query(None, pattern=r"^[a-z]{2,3}$"),
):
    items, total = service.list_documents(user, pagination, document_type, is_active, language)
    return ok(build_page(items, total, pagination))


@router.post(
    "",
    response_model=ApiResponse[DocumentRead],
    status_code=status.HTTP_201_CREATED,
    summary="Uploader un document",
    description="Upload multipart. Extensions acceptées : CV (pdf, doc, docx, odt), "
    "lettre (pdf, doc, docx, odt, txt), photo (jpg, png, webp). Le contenu réel du fichier "
    "est vérifié. Taille max : MAX_UPLOAD_SIZE_MB. Depuis Flutter, précisez le contentType "
    "du MultipartFile (sinon application/octet-stream est accepté).",
    responses=error_responses(401, 413, 422),
)
def upload_document(
    user: CurrentUser,
    service: Service,
    file: UploadFile = File(..., description="Fichier à envoyer"),
    document_type: DocumentType = Form(DocumentType.CV),
    title: str | None = Form(None, max_length=200),
    language: str | None = Form(None, pattern=r"^[a-z]{2,3}$"),
    target_job_title: str | None = Form(None, max_length=200),
    is_primary: bool = Form(False),
):
    document = service.upload(
        user,
        file,
        document_type,
        title=title,
        language=language,
        target_job_title=target_job_title,
        is_primary=is_primary,
    )
    return ok(document)


@router.get(
    "/{document_id}",
    response_model=ApiResponse[DocumentRead],
    summary="Détail d'un document",
    responses=error_responses(401, 404),
)
def get_document(document_id: uuid.UUID, user: CurrentUser, service: Service):
    return ok(service.get(user, document_id))


@router.patch(
    "/{document_id}",
    response_model=ApiResponse[DocumentRead],
    summary="Modifier un document (titre, langue, actif, principal...)",
    description="`is_primary=true` retire automatiquement ce statut aux autres documents du même type.",
    responses=error_responses(401, 404, 422),
)
def update_document(
    document_id: uuid.UUID, payload: DocumentUpdate, user: CurrentUser, service: Service
):
    return ok(service.update(user, document_id, payload))


@router.delete(
    "/{document_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Supprimer un document",
    responses=error_responses(401, 404),
)
def delete_document(document_id: uuid.UUID, user: CurrentUser, service: Service) -> None:
    service.delete(user, document_id)


@router.get(
    "/{document_id}/download",
    summary="Télécharger le fichier",
    description="Fichier privé : accessible uniquement par son propriétaire (token requis).",
    responses={200: {"content": {"application/octet-stream": {}}}, **error_responses(401, 404)},
    response_class=StreamingResponse,
)
def download_document(
    document_id: uuid.UUID, user: CurrentUser, service: Service, inline: bool = False
) -> StreamingResponse:
    document, chunks = service.stream(user, document_id)
    return file_response(document, chunks, inline=inline)
