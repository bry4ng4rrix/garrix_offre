"""Router principal : regroupe les routers de tous les modules sous /api/v1.

Pour ajouter un module : importez son router ici et ajoutez-le à `MODULE_ROUTERS`.
"""

from fastapi import APIRouter

from app.modules.ai.router import router as ai_router
from app.modules.applications.router import router as applications_router
from app.modules.audit.router import router as audit_router
from app.modules.auth.router import router as auth_router
from app.modules.companies.router import router as companies_router
from app.modules.contract_types.router import router as contract_types_router
from app.modules.documents.router import router as documents_router
from app.modules.experiences.router import router as experiences_router
from app.modules.integrations.n8n.router import router as n8n_router
from app.modules.job_titles.router import router as job_titles_router
from app.modules.jobs.router import router as jobs_router
from app.modules.matching.router import router as matching_router
from app.modules.monitoring.router import router as monitoring_router
from app.modules.notifications.router import router as notifications_router
from app.modules.preferences.router import router as preferences_router
from app.modules.profile.router import router as profile_router
from app.modules.recruiters.router import router as recruiters_router
from app.modules.scraping.router import router as scraping_router
from app.modules.skills.router import router as skills_router
from app.modules.sources.router import router as sources_router
from app.modules.users.router import router as users_router

MODULE_ROUTERS = [
    auth_router,
    users_router,
    profile_router,
    skills_router,
    experiences_router,
    job_titles_router,
    contract_types_router,
    preferences_router,
    companies_router,
    recruiters_router,
    sources_router,
    scraping_router,
    jobs_router,
    matching_router,
    applications_router,
    documents_router,
    notifications_router,
    monitoring_router,
    ai_router,
    n8n_router,
    audit_router,
]

api_router = APIRouter()
for module_router in MODULE_ROUTERS:
    api_router.include_router(module_router)
