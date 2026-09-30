"""Configuration centralisée de l'application.

Toutes les valeurs viennent des variables d'environnement (ou du fichier .env).
Pour ajouter un paramètre : ajoutez un attribut ici, puis documentez-le dans .env.example.
Les secrets sont typés `SecretStr` : ils ne s'affichent jamais dans les logs ou les repr().
"""

from functools import lru_cache
from typing import Annotated, Literal

from pydantic import Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

PLACEHOLDER_PREFIX = "change-me"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    # --- Application ---
    APP_NAME: str = "Garrix Offre API"
    APP_VERSION: str = "1.0.0"
    APP_ENV: Literal["development", "test", "production"] = "development"
    DEBUG: bool = False
    API_V1_PREFIX: str = "/api/v1"
    LOG_LEVEL: str = "INFO"
    LOG_FORMAT: Literal["json", "console"] = "json"
    CORS_ORIGINS: Annotated[list[str], NoDecode] = Field(default_factory=list)
    ALLOW_REGISTRATION: bool = True

    # --- Base de données ---
    DATABASE_URL: str = "postgresql+psycopg://garrix:garrix@localhost:5433/garrix_offre"
    DATABASE_POOL_SIZE: int = 10
    DATABASE_ECHO: bool = False

    # --- Redis / Celery ---
    REDIS_URL: str = "redis://localhost:6380/0"
    CELERY_BROKER_URL: str | None = None
    CELERY_TASK_ALWAYS_EAGER: bool = False

    # --- JWT / authentification ---
    JWT_SECRET_KEY: SecretStr
    JWT_ALGORITHM: str = "HS256"
    JWT_ACCESS_TOKEN_EXPIRE_MINUTES: int = Field(default=15, ge=1)
    JWT_REFRESH_TOKEN_EXPIRE_DAYS: int = Field(default=30, ge=1)

    # --- Sécurité HTTP ---
    RATE_LIMIT_ENABLED: bool = True
    RATE_LIMIT_PER_MINUTE: int = Field(default=120, ge=1)
    AUTH_RATE_LIMIT_PER_MINUTE: int = Field(default=10, ge=1)
    MAX_REQUEST_SIZE_MB: int = Field(default=2, ge=1)
    MAX_UPLOAD_SIZE_MB: int = Field(default=10, ge=1)

    # --- n8n ---
    N8N_WEBHOOK_SECRET: SecretStr
    N8N_BASE_URL: str = "http://localhost:5678"
    N8N_NOTIFICATION_WEBHOOK_URL: str | None = None
    NOTIFICATION_DELIVERY_MODE: Literal["backend", "n8n"] = "backend"

    # --- Telegram ---
    TELEGRAM_BOT_TOKEN: SecretStr | None = None
    TELEGRAM_CHAT_ID: str | None = None

    # --- Email (SMTP) ---
    SMTP_HOST: str | None = None
    SMTP_PORT: int = 587
    SMTP_USERNAME: str | None = None
    SMTP_PASSWORD: SecretStr | None = None
    SMTP_FROM: str | None = None
    SMTP_USE_TLS: bool = True
    SMTP_USE_SSL: bool = False
    SMTP_TIMEOUT_SECONDS: int = 20

    # --- Stockage des fichiers ---
    STORAGE_BACKEND: Literal["local"] = "local"
    STORAGE_PATH: str = "./storage"

    # --- Scraping ---
    SCRAPER_USER_AGENT: str = "GarrixOffreBot/1.0"
    SCRAPER_TIMEOUT_SECONDS: float = 20.0
    SCRAPER_DEFAULT_RATE_LIMIT: int = Field(default=30, ge=1)
    SCRAPER_MAX_JOBS_PER_RUN: int = Field(default=200, ge=1)
    ALLOW_PRIVATE_SOURCE_URLS: bool = False

    # API officielle France Travail (https://francetravail.io, application gratuite)
    FRANCE_TRAVAIL_CLIENT_ID: str | None = None
    FRANCE_TRAVAIL_CLIENT_SECRET: SecretStr | None = None

    # --- Cycle de vie des offres ---
    JOB_STALE_AFTER_DAYS: int = Field(default=30, ge=1)
    JOB_ARCHIVE_AFTER_DAYS: int = Field(default=60, ge=1)

    # --- Matching : valeurs par défaut (chaque utilisateur peut les modifier via l'API) ---
    MATCHING_SKILLS_WEIGHT: int = Field(default=40, ge=0, le=100)
    MATCHING_EXPERIENCE_WEIGHT: int = Field(default=20, ge=0, le=100)
    MATCHING_CONTRACT_WEIGHT: int = Field(default=15, ge=0, le=100)
    MATCHING_LOCATION_WEIGHT: int = Field(default=10, ge=0, le=100)
    MATCHING_SALARY_WEIGHT: int = Field(default=10, ge=0, le=100)
    MATCHING_LANGUAGE_WEIGHT: int = Field(default=5, ge=0, le=100)
    MATCHING_TITLE_WEIGHT: int = Field(default=10, ge=0, le=100)
    MATCHING_EXPERIENCE_LEVEL_WEIGHT: int = Field(default=10, ge=0, le=100)
    MATCHING_DEFAULT_THRESHOLD: int = Field(default=75, ge=0, le=100)

    # --- IA (optionnelle) ---
    AI_PROVIDER: Literal["none", "anthropic"] = "none"
    AI_API_KEY: SecretStr | None = None
    AI_MODEL: str | None = None
    AI_TIMEOUT_SECONDS: float = 120.0

    @field_validator("CORS_ORIGINS", mode="before")
    @classmethod
    def split_cors_origins(cls, value: object) -> object:
        """Accepte "http://a,http://b" en plus d'une vraie liste."""
        if isinstance(value, str):
            return [origin.strip() for origin in value.split(",") if origin.strip()]
        return value

    @field_validator(
        "TELEGRAM_BOT_TOKEN",
        "TELEGRAM_CHAT_ID",
        "SMTP_HOST",
        "SMTP_USERNAME",
        "SMTP_PASSWORD",
        "SMTP_FROM",
        "AI_API_KEY",
        "AI_MODEL",
        "N8N_NOTIFICATION_WEBHOOK_URL",
        "CELERY_BROKER_URL",
        "FRANCE_TRAVAIL_CLIENT_ID",
        "FRANCE_TRAVAIL_CLIENT_SECRET",
        mode="before",
    )
    @classmethod
    def empty_string_to_none(cls, value: object) -> object:
        """Dans un .env, `VAR=` signifie "non configuré"."""
        if isinstance(value, str) and not value.strip():
            return None
        return value

    @model_validator(mode="after")
    def check_secrets(self) -> "Settings":
        if len(self.JWT_SECRET_KEY.get_secret_value()) < 32:
            raise ValueError("JWT_SECRET_KEY doit contenir au moins 32 caractères.")
        if len(self.N8N_WEBHOOK_SECRET.get_secret_value()) < 16:
            raise ValueError("N8N_WEBHOOK_SECRET doit contenir au moins 16 caractères.")
        if self.is_production:
            if self.DEBUG:
                raise ValueError("DEBUG doit être false en production.")
            for name in ("JWT_SECRET_KEY", "N8N_WEBHOOK_SECRET"):
                secret: SecretStr = getattr(self, name)
                if secret.get_secret_value().startswith(PLACEHOLDER_PREFIX):
                    raise ValueError(f"{name} contient encore une valeur d'exemple.")
            if "*" in self.CORS_ORIGINS:
                raise ValueError("CORS_ORIGINS='*' est interdit en production.")
        return self

    # --- Propriétés pratiques ---

    @property
    def is_production(self) -> bool:
        return self.APP_ENV == "production"

    @property
    def celery_broker_url(self) -> str:
        return self.CELERY_BROKER_URL or self.REDIS_URL

    @property
    def max_request_size_bytes(self) -> int:
        return self.MAX_REQUEST_SIZE_MB * 1024 * 1024

    @property
    def max_upload_size_bytes(self) -> int:
        return self.MAX_UPLOAD_SIZE_MB * 1024 * 1024

    @property
    def telegram_enabled(self) -> bool:
        return bool(self.TELEGRAM_BOT_TOKEN and self.TELEGRAM_CHAT_ID)

    @property
    def email_enabled(self) -> bool:
        return bool(self.SMTP_HOST and self.SMTP_FROM)

    @property
    def ai_enabled(self) -> bool:
        return self.AI_PROVIDER != "none"


@lru_cache
def get_settings() -> Settings:
    """Retourne la configuration (lue une seule fois, puis mise en cache)."""
    return Settings()  # type: ignore[call-arg]  # les valeurs viennent de l'environnement
