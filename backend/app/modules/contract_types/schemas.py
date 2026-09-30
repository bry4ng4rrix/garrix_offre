import uuid

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.shared.schemas import ORMModel
from app.shared.utils import normalize_text, slugify

CODE_PATTERN = r"^[a-z0-9_]+$"


def clean_aliases(aliases: list[str]) -> list[str]:
    """Alias normalisés, sans doublon."""
    return sorted({normalize_text(alias) for alias in aliases if normalize_text(alias)})


class ContractTypeRead(ORMModel):
    id: uuid.UUID
    code: str
    name: str
    description: str | None
    aliases: list[str]
    is_active: bool
    sort_order: int


class ContractTypeCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    code: str | None = Field(
        default=None,
        max_length=50,
        pattern=CODE_PATTERN,
        description="Généré depuis le nom si absent",
    )
    description: str | None = Field(default=None, max_length=2000)
    aliases: list[str] = Field(default_factory=list, max_length=50)
    is_active: bool = True
    sort_order: int = Field(default=0, ge=0, le=1000)

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "name": "CDI",
                    "code": "cdi",
                    "aliases": ["permanent", "contrat a duree indeterminee"],
                }
            ]
        }
    )

    @field_validator("aliases")
    @classmethod
    def normalize_aliases(cls, value: list[str]) -> list[str]:
        return clean_aliases(value)

    def resolved_code(self) -> str:
        return self.code or slugify(self.name)


class ContractTypeUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=100)
    description: str | None = Field(default=None, max_length=2000)
    aliases: list[str] | None = Field(default=None, max_length=50)
    is_active: bool | None = None
    sort_order: int | None = Field(default=None, ge=0, le=1000)

    @field_validator("aliases")
    @classmethod
    def normalize_aliases(cls, value: list[str] | None) -> list[str] | None:
        return clean_aliases(value) if value is not None else None
