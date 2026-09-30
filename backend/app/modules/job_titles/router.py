import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, status

from app.api.dependencies import CurrentUser
from app.modules.job_titles.dependencies import get_job_title_service
from app.modules.job_titles.schemas import JobTitleCreate, JobTitleRead, JobTitleUpdate
from app.modules.job_titles.service import JobTitleService
from app.shared.schemas import ApiResponse, error_responses, ok

router = APIRouter(prefix="/job-titles", tags=["Job Titles"])

Service = Annotated[JobTitleService, Depends(get_job_title_service)]


@router.get(
    "",
    response_model=ApiResponse[list[JobTitleRead]],
    summary="Mes postes recherchés",
    responses=error_responses(401),
)
def list_job_titles(user: CurrentUser, service: Service, enabled_only: bool = False):
    return ok(service.list_titles(user, enabled_only))


@router.post(
    "",
    response_model=ApiResponse[JobTitleRead],
    status_code=status.HTTP_201_CREATED,
    summary="Ajouter un poste recherché",
    responses=error_responses(401, 409, 422),
)
def create_job_title(payload: JobTitleCreate, user: CurrentUser, service: Service):
    return ok(service.create(user, payload))


@router.get(
    "/{job_title_id}",
    response_model=ApiResponse[JobTitleRead],
    summary="Détail d'un poste recherché",
    responses=error_responses(401, 404),
)
def get_job_title(job_title_id: uuid.UUID, user: CurrentUser, service: Service):
    return ok(service.get(user, job_title_id))


@router.put(
    "/{job_title_id}",
    response_model=ApiResponse[JobTitleRead],
    summary="Modifier un poste recherché",
    responses=error_responses(401, 404, 409, 422),
)
def update_job_title(
    job_title_id: uuid.UUID, payload: JobTitleUpdate, user: CurrentUser, service: Service
):
    return ok(service.update(user, job_title_id, payload))


@router.delete(
    "/{job_title_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Supprimer un poste recherché",
    responses=error_responses(401, 404),
)
def delete_job_title(job_title_id: uuid.UUID, user: CurrentUser, service: Service) -> None:
    service.delete(user, job_title_id)
