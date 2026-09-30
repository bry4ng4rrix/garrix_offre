import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from app.shared.schemas import ORMModel


class MatchResultRead(ORMModel):
    """Résultat détaillé du matching d'une offre."""

    job_id: uuid.UUID
    score: int = Field(ge=0, le=100)
    matched_skills: list[str]
    missing_skills: list[str]
    experience_match: bool | None
    location_match: bool | None
    contract_match: bool | None
    salary_match: bool | None
    language_match: bool | None
    title_match: bool | None
    experience_level_match: bool | None
    reasons: list[str]
    breakdown: dict[str, Any] = Field(description="Sous-score (0-1) et poids de chaque critère")
    computed_at: datetime

    model_config = ConfigDict(
        from_attributes=True,
        json_schema_extra={
            "examples": [
                {
                    "job_id": "5f0c3c1e-8a52-4a36-9f5e-2b0f1c2d3e4f",
                    "score": 91,
                    "matched_skills": ["Python", "Django", "React"],
                    "missing_skills": ["Kubernetes"],
                    "experience_match": True,
                    "location_match": True,
                    "contract_match": True,
                    "salary_match": True,
                    "language_match": True,
                    "title_match": True,
                    "experience_level_match": True,
                    "reasons": ["Compétences correspondantes : 3/4", "Contrat recherché (cdi)"],
                    "breakdown": {"skills": {"score": 0.8, "weight": 40}},
                    "computed_at": "2026-09-30T08:00:00Z",
                }
            ]
        },
    )


class MatchingSettingsRead(ORMModel):
    skills_weight: int
    experience_weight: int
    contract_weight: int
    location_weight: int
    salary_weight: int
    language_weight: int
    title_weight: int
    experience_level_weight: int


class MatchingSettingsUpdate(BaseModel):
    """Poids relatifs (0 = critère ignoré). Le score final est toujours ramené sur 100."""

    skills_weight: int | None = Field(default=None, ge=0, le=100)
    experience_weight: int | None = Field(default=None, ge=0, le=100)
    contract_weight: int | None = Field(default=None, ge=0, le=100)
    location_weight: int | None = Field(default=None, ge=0, le=100)
    salary_weight: int | None = Field(default=None, ge=0, le=100)
    language_weight: int | None = Field(default=None, ge=0, le=100)
    title_weight: int | None = Field(default=None, ge=0, le=100)
    experience_level_weight: int | None = Field(default=None, ge=0, le=100)

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "skills_weight": 40,
                    "experience_weight": 20,
                    "contract_weight": 15,
                    "location_weight": 10,
                    "salary_weight": 10,
                    "language_weight": 5,
                }
            ]
        }
    )


class RecalculateResult(BaseModel):
    status: str = Field(description='"queued" (tâche de fond) ou "done"')
    jobs_matched: int | None = None
