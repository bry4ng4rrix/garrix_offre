"""Validation des fichiers uploadés (RG-11).

Trois contrôles :
1. l'extension est autorisée pour ce type de document ;
2. le type MIME déclaré par le client est cohérent (ou générique : application/octet-stream) ;
3. le contenu réel du fichier (ses premiers octets, la "signature") correspond à l'extension.
   On ne fait jamais confiance au nom ou au type annoncés par le client.
La taille maximale est contrôlée pendant l'écriture (voir DocumentService).
"""

from dataclasses import dataclass
from pathlib import PurePath

from app.core.exceptions import BusinessRuleError
from app.shared.enums import DocumentType

MIME_TYPES = {
    "pdf": "application/pdf",
    "doc": "application/msword",
    "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "odt": "application/vnd.oasis.opendocument.text",
    "txt": "text/plain",
    "png": "image/png",
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "webp": "image/webp",
}

ALLOWED_EXTENSIONS: dict[DocumentType, set[str]] = {
    DocumentType.CV: {"pdf", "doc", "docx", "odt"},
    DocumentType.COVER_LETTER: {"pdf", "doc", "docx", "odt", "txt"},
    DocumentType.PHOTO: {"jpg", "jpeg", "png", "webp"},
    DocumentType.OTHER: {"pdf", "doc", "docx", "odt", "txt", "png", "jpg", "jpeg", "webp"},
}

GENERIC_MIME_TYPES = {"application/octet-stream", "binary/octet-stream", ""}
HEADER_SIZE = 16


def _has_signature(extension: str, header: bytes) -> bool:
    match extension:
        case "pdf":
            return header.startswith(b"%PDF-")
        case "png":
            return header.startswith(b"\x89PNG\r\n\x1a\n")
        case "jpg" | "jpeg":
            return header.startswith(b"\xff\xd8\xff")
        case "webp":
            return header[:4] == b"RIFF" and header[8:12] == b"WEBP"
        case "docx" | "odt":
            return header.startswith(b"PK\x03\x04")  # archive ZIP
        case "doc":
            return header.startswith(b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1")  # format OLE
        case "txt":
            return b"\x00" not in header
    return False


@dataclass(frozen=True)
class ValidatedFile:
    extension: str
    mime_type: str
    safe_filename: str


def safe_filename(filename: str) -> str:
    """Garde uniquement le nom (sans chemin) et des caractères sûrs."""
    name = PurePath(filename.replace("\\", "/")).name
    cleaned = "".join(char if char.isalnum() or char in "._- " else "_" for char in name).strip()
    return cleaned[:200] or "document"


def validate_upload(
    filename: str | None, declared_mime: str | None, header: bytes, document_type: DocumentType
) -> ValidatedFile:
    if not filename or "." not in filename:
        raise BusinessRuleError("The file must have an extension", code="INVALID_FILE_EXTENSION")
    extension = filename.rsplit(".", 1)[1].lower()
    allowed = ALLOWED_EXTENSIONS[document_type]
    if extension not in allowed:
        raise BusinessRuleError(
            f"Extension .{extension} is not allowed for {document_type.value}",
            code="INVALID_FILE_EXTENSION",
            details={"allowed": sorted(allowed)},
        )

    expected_mime = MIME_TYPES[extension]
    declared = (declared_mime or "").split(";")[0].strip().lower()
    if declared not in GENERIC_MIME_TYPES and declared != expected_mime:
        raise BusinessRuleError(
            "The declared MIME type does not match the file extension",
            code="INVALID_MIME_TYPE",
            details={"expected": expected_mime, "received": declared},
        )

    if not header:
        raise BusinessRuleError("The file is empty", code="EMPTY_FILE")
    if not _has_signature(extension, header):
        raise BusinessRuleError(
            "The file content does not match its extension", code="INVALID_FILE_CONTENT"
        )
    return ValidatedFile(
        extension=extension, mime_type=expected_mime, safe_filename=safe_filename(filename)
    )
