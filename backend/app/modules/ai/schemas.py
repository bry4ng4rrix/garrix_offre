from enum import StrEnum

from pydantic import BaseModel, Field


class GeneratedBy(StrEnum):
    AI = "ai"
    RULES = "rules"


class GenerationKind(StrEnum):
    COVER_LETTER = "cover_letter"
    APPLICATION_EMAIL = "application_email"
    JOB_SUMMARY = "job_summary"
    RECRUITER_REPLY = "recruiter_reply"


class AIStatus(BaseModel):
    enabled: bool
    provider: str
    model: str | None


class JobAnalysis(BaseModel):
    summary: str
    responsibilities: list[str]
    required_skills: list[str]
    preferred_skills: list[str]
    experience_level: str
    min_years_experience: int
    languages: list[str]
    remote_policy: str
    highlights: list[str]
    red_flags: list[str]
    requirements: dict[str, object] = Field(description="must_have, nice_to_have, education...")
    generated_by: GeneratedBy


class GeneratedText(BaseModel):
    kind: GenerationKind
    subject: str | None = None
    content: str
    generated_by: GeneratedBy


class ResponseAnalysis(BaseModel):
    response_type: str
    summary: str
    suggested_status: str
    next_steps: list[str]
    generated_by: GeneratedBy
