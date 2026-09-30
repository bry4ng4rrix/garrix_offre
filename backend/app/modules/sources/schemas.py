import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, HttpUrl

from app.shared.enums import FetchMode, SourceCategory, SourceType
from app.shared.schemas import ORMModel


class SourceRead(ORMModel):
    id: uuid.UUID
    name: str
    type: SourceType
    category: SourceCategory
    adapter: str | None
    fetch_mode: FetchMode
    base_url: str | None
    enabled: bool
    scraping_enabled: bool
    priority: int
    configuration: dict[str, Any]
    rate_limit: int | None
    terms_reviewed: bool
    last_run_at: datetime | None
    last_success_at: datetime | None
    last_error: str | None
    notes: str | None
    created_at: datetime
    updated_at: datetime


class SourceBase(BaseModel):
    category: SourceCategory = SourceCategory.JOBS
    adapter: str | None = Field(
        default=None, max_length=100, description="Voir GET /scraping/adapters"
    )
    fetch_mode: FetchMode = FetchMode.BACKEND
    base_url: HttpUrl | None = None
    enabled: bool = True
    scraping_enabled: bool = False
    priority: int = Field(default=5, ge=1, le=10)
    configuration: dict[str, Any] = Field(default_factory=dict)
    rate_limit: int | None = Field(default=None, ge=1, le=600, description="Requêtes / minute")
    terms_reviewed: bool = Field(
        default=False,
        description="Les conditions d'utilisation du site autorisent la collecte automatique",
    )
    notes: str | None = Field(default=None, max_length=5000)


class SourceCreate(SourceBase):
    name: str = Field(min_length=1, max_length=150)
    type: SourceType

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "name": "Flux RSS Python",
                    "type": "rss",
                    "adapter": "rss_feed",
                    "base_url": "https://example.com",
                    "scraping_enabled": True,
                    "configuration": {"feed_url": "https://example.com/jobs.rss"},
                    "rate_limit": 10,
                }
            ]
        }
    )


class SourceUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=150)
    type: SourceType | None = None
    category: SourceCategory | None = None
    adapter: str | None = Field(default=None, max_length=100)
    fetch_mode: FetchMode | None = None
    base_url: HttpUrl | None = None
    enabled: bool | None = None
    scraping_enabled: bool | None = None
    priority: int | None = Field(default=None, ge=1, le=10)
    configuration: dict[str, Any] | None = None
    rate_limit: int | None = Field(default=None, ge=1, le=600)
    terms_reviewed: bool | None = None
    notes: str | None = Field(default=None, max_length=5000)
