"""Énumérations partagées par plusieurs modules.

Toutes les valeurs sont des chaînes en minuscules : c'est ce que reçoit et envoie l'API.
Elles sont stockées en VARCHAR en base (voir `enum_column` dans core/database.py),
donc ajouter une valeur ici ne nécessite pas de migration.
"""

from enum import StrEnum


class SkillLevel(StrEnum):
    BEGINNER = "beginner"
    INTERMEDIATE = "intermediate"
    ADVANCED = "advanced"
    EXPERT = "expert"


class Priority(StrEnum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class LanguageLevel(StrEnum):
    BASIC = "basic"
    INTERMEDIATE = "intermediate"
    FLUENT = "fluent"
    NATIVE = "native"


class Availability(StrEnum):
    IMMEDIATE = "immediate"
    ONE_WEEK = "one_week"
    TWO_WEEKS = "two_weeks"
    ONE_MONTH = "one_month"
    TWO_MONTHS = "two_months"
    THREE_MONTHS = "three_months"
    NOT_AVAILABLE = "not_available"


class Mobility(StrEnum):
    NONE = "none"
    LOCAL = "local"
    REGIONAL = "regional"
    NATIONAL = "national"
    INTERNATIONAL = "international"


class SalaryPeriod(StrEnum):
    YEAR = "year"
    MONTH = "month"
    DAY = "day"
    HOUR = "hour"


class WorkTime(StrEnum):
    FULL_TIME = "full_time"
    PART_TIME = "part_time"


class JobStatus(StrEnum):
    """Cycle de vie global d'une offre (UML 17).

    NEW -> ACTIVE (validée) -> EXPIRED -> ARCHIVED.
    L'état IGNORED est propre à chaque utilisateur (voir JobUserState).
    """

    NEW = "new"
    ACTIVE = "active"
    EXPIRED = "expired"
    ARCHIVED = "archived"


class SkillRequirement(StrEnum):
    REQUIRED = "required"
    PREFERRED = "preferred"


class SourceType(StrEnum):
    API = "api"
    RSS = "rss"
    HTML = "html"
    MANUAL = "manual"
    WEBHOOK = "webhook"


class SourceCategory(StrEnum):
    """Nature d'une source : offres d'emploi, missions de clients (freelance) ou service de données."""

    JOBS = "jobs"
    CLIENTS = "clients"
    SERVICES = "services"


class FetchMode(StrEnum):
    """Qui récupère les offres d'une source : un adapter FastAPI, ou n8n directement."""

    BACKEND = "backend"
    N8N = "n8n"


class ScrapingRunStatus(StrEnum):
    """États d'une collecte (UML 19)."""

    PENDING = "pending"
    RUNNING = "running"
    SUCCESS = "success"
    PARTIAL_SUCCESS = "partial_success"
    FAILED = "failed"
    CANCELLED = "cancelled"


class ScrapingTrigger(StrEnum):
    MANUAL = "manual"
    N8N = "n8n"
    API = "api"


class DataOrigin(StrEnum):
    """Provenance d'une donnée d'entreprise."""

    MANUAL = "manual"
    SCRAPING = "scraping"
    API = "api"
    N8N = "n8n"


class ContactSource(StrEnum):
    """Provenance d'une coordonnée de recruteur (jamais inventée)."""

    JOB_LISTING = "job_listing"
    COMPANY_WEBSITE = "company_website"
    PUBLIC_PROFILE = "public_profile"
    API = "api"
    MANUAL = "manual"
    OTHER = "other"


class ApplicationStatus(StrEnum):
    """États d'une candidature (UML 18 / RG-10)."""

    NOT_APPLIED = "not_applied"
    PREPARING = "preparing"
    READY = "ready"
    SUBMITTED = "submitted"
    FOLLOW_UP = "follow_up"
    INTERVIEW = "interview"
    OFFER = "offer"
    REJECTED = "rejected"
    WITHDRAWN = "withdrawn"


class SubmissionMethod(StrEnum):
    EMAIL = "email"
    WEBSITE = "website"
    OTHER = "other"


class RecruiterResponseType(StrEnum):
    INTERVIEW = "interview"
    REJECTION = "rejection"
    OFFER = "offer"
    INFORMATION_REQUEST = "information_request"
    ACKNOWLEDGEMENT = "acknowledgement"
    OTHER = "other"


class DocumentType(StrEnum):
    CV = "cv"
    COVER_LETTER = "cover_letter"
    PHOTO = "photo"
    OTHER = "other"


class NotificationType(StrEnum):
    NEW_JOB = "new_job"
    HIGH_MATCH = "high_match"
    APPLICATION_STATUS = "application_status"
    RECRUITER_RESPONSE = "recruiter_response"
    SCRAPING_ERROR = "scraping_error"
    SYSTEM = "system"
    MONITORING = "monitoring"


class ActorType(StrEnum):
    """Qui a déclenché une action (audit)."""

    USER = "user"
    N8N = "n8n"
    SYSTEM = "system"
