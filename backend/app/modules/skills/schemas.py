import uuid

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.shared.enums import Priority, SkillLevel
from app.shared.schemas import ORMModel
from app.shared.utils import normalize_text

CATEGORY_CODE_PATTERN = r"^[a-z0-9_]+$"


class SkillCategoryRead(ORMModel):
    id: uuid.UUID
    code: str
    name: str
    description: str | None


class SkillCategoryCreate(BaseModel):
    code: str = Field(min_length=1, max_length=50, pattern=CATEGORY_CODE_PATTERN)
    name: str = Field(min_length=1, max_length=100)
    description: str | None = Field(default=None, max_length=1000)


class SkillCategoryUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=100)
    description: str | None = Field(default=None, max_length=1000)


class CatalogSkillRead(ORMModel):
    """Compétence du catalogue global."""

    id: uuid.UUID
    name: str
    category: str | None = Field(validation_alias="category_code")
    aliases: list[str]


class CatalogSkillUpdate(BaseModel):
    category: str | None = Field(default=None, max_length=50)
    aliases: list[str] | None = Field(default=None, max_length=50)

    @field_validator("aliases")
    @classmethod
    def normalize_aliases(cls, value: list[str] | None) -> list[str] | None:
        if value is None:
            return None
        return sorted({normalize_text(alias) for alias in value if normalize_text(alias)})


class ProfileSkillRead(ORMModel):
    """Compétence du profil, telle que renvoyée par /api/v1/skills."""

    id: uuid.UUID
    skill_id: uuid.UUID
    name: str
    category: str | None = Field(validation_alias="category_code")
    level: SkillLevel
    years_experience: float | None
    priority: Priority
    enabled: bool


class ProfileSkillCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    category: str | None = Field(default=None, max_length=50, description="Code de catégorie")
    level: SkillLevel = SkillLevel.INTERMEDIATE
    years_experience: float | None = Field(default=None, ge=0, le=60)
    priority: Priority = Priority.MEDIUM
    enabled: bool = True

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "name": "Python",
                    "category": "backend",
                    "level": "advanced",
                    "years_experience": 3,
                    "priority": "high",
                    "enabled": True,
                }
            ]
        }
    )

    @field_validator("name")
    @classmethod
    def strip_name(cls, value: str) -> str:
        value = value.strip()
        if not normalize_text(value):
            raise ValueError("Skill name must contain letters or digits")
        return value


class ProfileSkillUpdate(BaseModel):
    category: str | None = Field(default=None, max_length=50)
    level: SkillLevel | None = None
    years_experience: float | None = Field(default=None, ge=0, le=60)
    priority: Priority | None = None
    enabled: bool | None = None
