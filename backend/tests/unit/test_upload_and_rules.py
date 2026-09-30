import io
from pathlib import Path

import pytest

from app.core.exceptions import BusinessRuleError
from app.modules.applications import rules
from app.modules.documents.storage import LocalStorageService
from app.modules.documents.validation import safe_filename, validate_upload
from app.shared.enums import ActorType, ApplicationStatus, DocumentType


def test_valid_pdf_upload() -> None:
    result = validate_upload("CV Jane.pdf", "application/pdf", b"%PDF-1.7 ...", DocumentType.CV)
    assert result.extension == "pdf"
    assert result.mime_type == "application/pdf"


def test_generic_mime_type_is_accepted_when_content_matches() -> None:
    result = validate_upload(
        "photo.png", "application/octet-stream", b"\x89PNG\r\n\x1a\n...", DocumentType.PHOTO
    )
    assert result.mime_type == "image/png"


@pytest.mark.parametrize(
    ("filename", "mime", "header", "document_type", "code"),
    [
        ("virus.exe", "application/octet-stream", b"MZ", DocumentType.CV, "INVALID_FILE_EXTENSION"),
        ("photo.pdf", "application/pdf", b"%PDF-", DocumentType.PHOTO, "INVALID_FILE_EXTENSION"),
        ("cv.pdf", "image/png", b"%PDF-", DocumentType.CV, "INVALID_MIME_TYPE"),
        ("cv.pdf", "application/pdf", b"<html>", DocumentType.CV, "INVALID_FILE_CONTENT"),
        ("cv.pdf", "application/pdf", b"", DocumentType.CV, "EMPTY_FILE"),
        ("noextension", "application/pdf", b"%PDF-", DocumentType.CV, "INVALID_FILE_EXTENSION"),
    ],
)
def test_invalid_uploads(
    filename: str, mime: str, header: bytes, document_type: DocumentType, code: str
) -> None:
    with pytest.raises(BusinessRuleError) as error:
        validate_upload(filename, mime, header, document_type)
    assert error.value.code == code


def test_safe_filename_strips_paths() -> None:
    assert safe_filename("../../etc/passwd") == "passwd"
    assert safe_filename("C:\\Users\\me\\cv<script>.pdf") == "cv_script_.pdf"


def test_local_storage_blocks_path_traversal(tmp_path: Path) -> None:
    storage = LocalStorageService(tmp_path)
    storage.save("user/file.txt", io.BytesIO(b"hello"))
    assert storage.read_bytes("user/file.txt") == b"hello"
    assert b"".join(storage.iter_chunks("user/file.txt")) == b"hello"
    with pytest.raises(ValueError):
        storage.save("../outside.txt", io.BytesIO(b"x"))
    storage.delete("user/file.txt")
    assert not storage.exists("user/file.txt")


def test_application_lifecycle_rules() -> None:
    s = ApplicationStatus
    assert rules.can_transition(s.NOT_APPLIED, s.PREPARING)
    assert rules.can_transition(s.READY, s.SUBMITTED)
    assert not rules.can_transition(s.PREPARING, s.SUBMITTED)
    assert not rules.can_transition(s.REJECTED, s.INTERVIEW)
    assert not rules.can_transition(s.WITHDRAWN, s.PREPARING)
    # SUBMITTED uniquement via /submit (confirmation explicite)
    assert not rules.actor_may_set(ActorType.USER, s.SUBMITTED)
    assert not rules.actor_may_set(ActorType.N8N, s.SUBMITTED)
    assert rules.actor_may_set(ActorType.N8N, s.INTERVIEW)
    assert not rules.actor_may_set(ActorType.N8N, s.WITHDRAWN)


def test_every_status_has_transitions_defined() -> None:
    assert set(rules.ALLOWED_TRANSITIONS) == set(ApplicationStatus)
