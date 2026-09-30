import uuid
from datetime import date

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.shared.enums import Priority, SkillLevel
from app.shared.schemas import ORMModel
from app.shared.utils import normalize_text

# --- Niveaux d'expérience (référentiel) ---


class ExperienceLevelRead(ORMModel):
    id: uuid.UUID
    code: str
    name: str
    rank: int
    min_years: int
    aliases: list[str]
    description: str | None


class ExperienceLevelCreate(BaseModel):
    code: str = Field(min_length=1, max_length=40, pattern=r"^[a-z0-9_]+$")
    name: str = Field(min_length=1, max_length=100)
    rank: int = Field(ge=0, le=100, description="Ordre croissant de séniorité")
    min_years: int = Field(default=0, ge=0, le=60)
    aliases: list[str] = Field(default_factory=list, max_length=50)
    description: str | None = Field(default=None, max_length=1000)

    @field_validator("aliases")
    @classmethod
    def normalize_aliases(cls, value: list[str]) -> list[str]:
        return sorted({normalize_text(alias) for alias in value if normalize_text(alias)})


class ExperienceLevelUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=100)
    rank: int | None = Field(default=None, ge=0, le=100)
    min_years: int | None = Field(default=None, ge=0, le=60)
    aliases: list[str] | None = Field(default=None, max_length=50)
    description: str | None = Field(default=None, max_length=1000)

    @field_validator("aliases")
    @classmethod
    def normalize_aliases(cls, value: list[str] | None) -> list[str] | None:
        if value is None:
            return None
        return sorted({normalize_text(alias) for alias in value if normalize_text(alias)})


# --- Parcours professionnel ---


class ExperienceBase(BaseModel):
    company_name: str = Field(min_length=1, max_length=200)
    job_title: str = Field(min_length=1, max_length=200)
    location: str | None = Field(default=None, max_length=200)
    start_date: date
    end_date: date | None = None
    is_current: bool = False
    description: str | None = Field(default=None, max_length=5000)
    technologies: list[str] = Field(default_factory=list, max_length=50)

    @model_validator(mode="after")
    def check_dates(self) -> "ExperienceBase":
        if self.end_date and self.end_date < self.start_date:
            raise ValueError("end_date must be after start_date")
        if self.is_current and self.end_date:
            raise ValueError("A current experience cannot have an end_date")
        return self


class ExperienceCreate(ExperienceBase):
    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "company_name": "Exemple SAS",
                    "job_title": "Développeur Full Stack",
                    "start_date": "2022-01-01",
                    "is_current": True,
                    "technologies": ["Python", "Django", "React"],
                }
            ]
        }
    )


class ExperienceUpdate(ExperienceBase):
    """PUT : remplace toute l'expérience."""


class ExperienceRead(ORMModel):
    id: uuid.UUID
    company_name: str
    job_title: str
    location: str | None
    start_date: date
    end_date: date | None
    is_current: bool
    description: str | None
    technologies: list[str]
    duration_years: float


# --- Technologies / expériences recherchées ---


class ExperiencePreferenceRead(ORMModel):
    id: uuid.UUID
    skill_id: uuid.UUID
    technology: str
    category: str | None = Field(validation_alias="category_code")
    level: SkillLevel
    priority: Priority
    min_years: int
    is_required: bool
    enabled: bool


class ExperiencePreferenceCreate(BaseModel):
    technology: str = Field(min_length=1, max_length=100)
    category: str | None = Field(default=None, max_length=50)
    level: SkillLevel = SkillLevel.INTERMEDIATE
    priority: Priority = Priority.MEDIUM
    min_years: int = Field(default=0, ge=0, le=60)
    is_required: bool = False
    enabled: bool = True

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "technology": "React",
                    "category": "frontend",
                    "level": "advanced",
                    "priority": "high",
                    "min_years": 2,
                    "is_required": True,
                }
            ]
        }
    )


class ExperiencePreferenceUpdate(BaseModel):
    level: SkillLevel | None = None
    priority: Priority | None = None
    min_years: int | None = Field(default=None, ge=0, le=60)
    is_required: bool | None = None
    enabled: bool | None = None
