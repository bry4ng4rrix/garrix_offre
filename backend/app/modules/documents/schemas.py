import uuid
from datetime import datetime

from pydantic import BaseModel, Field, computed_field

from app.shared.enums import DocumentType
from app.shared.schemas import ORMModel


class DocumentRead(ORMModel):
    id: uuid.UUID
    document_type: DocumentType
    title: str
    original_filename: str
    mime_type: str
    extension: str
    size_bytes: int
    language: str | None
    target_job_title: str | None
    is_active: bool
    is_primary: bool
    created_at: datetime

    @computed_field  # type: ignore[prop-decorator]
    @property
    def download_url(self) -> str:
        return f"/api/v1/documents/{self.id}/download"


class DocumentUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    language: str | None = Field(default=None, pattern=r"^[a-z]{2,3}$")
    target_job_title: str | None = Field(default=None, max_length=200)
    is_active: bool | None = None
    is_primary: bool | None = None
