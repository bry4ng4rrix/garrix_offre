from datetime import datetime

from fastapi import Query

from app.api.dependencies import DbSession
from app.core.exceptions import BadRequestError
from app.modules.jobs.repository import NO_COUNTRY, JobFilters
from app.modules.jobs.schemas import JobSortField, JobStatusFilter
from app.modules.jobs.service import JobService
from app.shared.enums import SourceCategory


def get_job_service(session: DbSession) -> JobService:
    return JobService(session)


def job_filters(
    search: str | None = Query(
        None, max_length=200, description="Texte dans le titre, la description ou l'entreprise"
    ),
    min_score: int | None = Query(None, ge=0, le=100, description="Score de matching minimum"),
    contract_type: str | None = Query(
        None, max_length=50, description="Code du contrat (cdi, freelance...)"
    ),
    remote: bool | None = Query(None, description="true = télétravail complet uniquement"),
    location: str | None = Query(None, max_length=100, description="Ville ou pays"),
    skill: str | None = Query(None, max_length=100, description="Compétence demandée (ex: Python)"),
    company: str | None = Query(None, max_length=200, description="Nom ou id d'entreprise"),
    experience_level: str | None = Query(None, max_length=40, description="junior, mid, senior..."),
    source: str | None = Query(None, max_length=150, description="Nom ou id de source"),
    source_category: list[SourceCategory] | None = Query(
        None,
        description="jobs (emplois), clients (missions freelance), services (API d'offres). "
        "Répétable : ?source_category=jobs&source_category=services",
    ),
    country: list[str] | None = Query(
        None,
        description=f"Pays de l'offre (ex. France), répétable. {NO_COUNTRY!r} = offres sans pays "
        "(souvent du télétravail mondial). La liste des pays : GET /jobs/countries",
    ),
    status: JobStatusFilter | None = Query(
        None, description="Par défaut : offres NEW/ACTIVE non ignorées"
    ),
    published_after: datetime | None = None,
    published_before: datetime | None = None,
    sort_by: JobSortField = JobSortField.PUBLISHED_AT,
    sort_order: str = Query("desc", pattern="^(asc|desc)$"),
) -> JobFilters:
    """Dépendance FastAPI : lit les filtres de GET /jobs dans l'URL."""
    return JobFilters(
        search=search,
        min_score=min_score,
        contract_type=contract_type,
        remote=remote,
        location=location,
        skill=skill,
        company=company,
        experience_level=experience_level,
        source=source,
        source_category=source_category,
        country=_checked_countries(country),
        status=status,
        published_after=published_after,
        published_before=published_before,
        sort_by=sort_by,
        sort_desc=sort_order == "desc",
    )


def _checked_countries(values: list[str] | None) -> list[str] | None:
    if not values:
        return None
    if len(values) > 50 or any(len(value) > 100 for value in values):
        raise BadRequestError("Too many or too long country values", code="INVALID_COUNTRY_FILTER")
    return values
