import uuid

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.shared.enums import Priority
from app.shared.schemas import ORMModel
from app.shared.utils import normalize_text


class JobTitleRead(ORMModel):
    id: uuid.UUID
    title: str
    priority: Priority
    enabled: bool


class JobTitleCreate(BaseModel):
    title: str = Field(min_length=2, max_length=200)
    priority: Priority = Priority.MEDIUM
    enabled: bool = True

    model_config = ConfigDict(
        json_schema_extra={"examples": [{"title": "Full Stack Developer", "priority": "high"}]}
    )

    @field_validator("title")
    @classmethod
    def check_title(cls, value: str) -> str:
        if not normalize_text(value):
            raise ValueError("Title must contain letters or digits")
        return value.strip()


class JobTitleUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=2, max_length=200)
    priority: Priority | None = None
    enabled: bool | None = None

    @field_validator("title")
    @classmethod
    def check_title(cls, value: str | None) -> str | None:
        if value is not None and not normalize_text(value):
            raise ValueError("Title must contain letters or digits")
        return value.strip() if value else value
