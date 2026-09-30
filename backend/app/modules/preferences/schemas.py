from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.shared.enums import SalaryPeriod
from app.shared.geo import normalize_country

LANGUAGE_CODE_PATTERN = r"^[a-z]{2,3}$"
CURRENCY_PATTERN = r"^[A-Z]{3}$"


class LocationPreference(BaseModel):
    city: str | None = Field(default=None, max_length=100)
    country: str | None = Field(default=None, max_length=100)

    @model_validator(mode="after")
    def check_not_empty(self) -> "LocationPreference":
        if not (self.city or self.country):
            raise ValueError("A location needs a city or a country")
        self.country = normalize_country(self.country)
        self.city = self.city.strip() if self.city else None
        return self


class PreferencesRead(BaseModel):
    job_titles: list[str]
    contract_types: list[str]
    skills: list[str]
    experience_levels: list[str]
    locations: list[LocationPreference]
    remote: bool
    hybrid: bool
    onsite: bool
    minimum_salary: int | None
    currency: str
    salary_period: SalaryPeriod
    languages: list[str]
    matching_threshold: int


class PreferencesUpdate(BaseModel):
    """Mise à jour partielle : les champs absents ne sont pas modifiés.

    - `job_titles` / `skills` : les éléments listés sont activés, les autres désactivés
      (leurs réglages détaillés restent disponibles via /job-titles et /experience-preferences).
    - `contract_types` / `experience_levels` : codes des référentiels.
    """

    job_titles: list[str] | None = Field(default=None, max_length=50)
    contract_types: list[str] | None = Field(default=None, max_length=20)
    skills: list[str] | None = Field(default=None, max_length=100)
    experience_levels: list[str] | None = Field(default=None, max_length=10)
    locations: list[LocationPreference] | None = Field(default=None, max_length=20)
    remote: bool | None = None
    hybrid: bool | None = None
    onsite: bool | None = None
    minimum_salary: int | None = Field(default=None, ge=0, le=100_000_000)
    currency: str | None = Field(default=None, pattern=CURRENCY_PATTERN)
    salary_period: SalaryPeriod | None = None
    languages: list[str] | None = Field(default=None, max_length=10)
    matching_threshold: int | None = Field(default=None, ge=0, le=100)

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "job_titles": ["Full Stack Developer", "Python Developer"],
                    "contract_types": ["cdi", "freelance"],
                    "skills": ["Python", "React"],
                    "experience_levels": ["mid", "senior"],
                    "locations": [{"city": "Paris", "country": "France"}],
                    "remote": True,
                    "hybrid": False,
                    "minimum_salary": 900,
                    "currency": "EUR",
                    "salary_period": "month",
                    "languages": ["fr", "en"],
                    "matching_threshold": 75,
                }
            ]
        }
    )

    @field_validator("languages")
    @classmethod
    def normalize_languages(cls, value: list[str] | None) -> list[str] | None:
        if value is None:
            return None
        codes = sorted({code.strip().lower() for code in value if code.strip()})
        for code in codes:
            if not code.isalpha() or not 2 <= len(code) <= 3:
                raise ValueError(f"Invalid language code: {code} (use ISO codes like 'fr')")
        return codes

    @field_validator("currency", mode="before")
    @classmethod
    def upper_currency(cls, value: object) -> object:
        return value.upper() if isinstance(value, str) else value
