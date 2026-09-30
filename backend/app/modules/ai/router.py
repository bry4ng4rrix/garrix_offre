import uuid

from fastapi import APIRouter

from app.api.dependencies import CurrentUser, DbSession
from app.core.exceptions import NotFoundError
from app.modules.ai.schemas import AIStatus, JobAnalysis
from app.modules.ai.service import AIService
from app.modules.jobs.models import Job
from app.shared.schemas import ApiResponse, error_responses, ok

router = APIRouter(prefix="/ai", tags=["AI"])


@router.get(
    "/status",
    response_model=ApiResponse[AIStatus],
    summary="État de l'IA (activée, fournisseur, modèle)",
    responses=error_responses(401),
)
def ai_status(_user: CurrentUser, session: DbSession):
    return ok(AIService(session).status())


@router.post(
    "/jobs/{job_id}/analyze",
    response_model=ApiResponse[JobAnalysis],
    summary="Analyser une offre",
    description="Résumé, compétences, exigences, niveau, télétravail. Utilise l'IA si elle est "
    "configurée, sinon des règles déterministes (`generated_by` indique la méthode).",
    responses=error_responses(401, 404),
)
def analyze_job(job_id: uuid.UUID, _user: CurrentUser, session: DbSession):
    job = session.get(Job, job_id)
    if job is None:
        raise NotFoundError("Job not found", code="JOB_NOT_FOUND")
    return ok(AIService(session).analyze_job(job))
