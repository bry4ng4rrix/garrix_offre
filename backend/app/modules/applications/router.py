import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, status

from app.api.dependencies import CurrentUser
from app.modules.ai.schemas import GeneratedText
from app.modules.applications.dependencies import get_application_service, get_response_service
from app.modules.applications.responses import RecruiterResponseService
from app.modules.applications.schemas import (
    ApplicationCreate,
    ApplicationRead,
    ApplicationUpdate,
    GenerateRequest,
    PrepareRequest,
    RecruiterResponseCreate,
    RecruiterResponseRead,
    RecruiterResponseUpdate,
    StatusChange,
    StatusHistoryRead,
    SubmitRequest,
)
from app.modules.applications.service import ApplicationService
from app.shared.enums import ApplicationStatus
from app.shared.pagination import Page, PaginationParams, build_page
from app.shared.schemas import ApiResponse, error_responses, ok

router = APIRouter(prefix="/applications", tags=["Applications"])

Service = Annotated[ApplicationService, Depends(get_application_service)]
Responses = Annotated[RecruiterResponseService, Depends(get_response_service)]


# --- Réponses des recruteurs (déclarées avant /{application_id}) ---


@router.get(
    "/responses",
    response_model=ApiResponse[Page[RecruiterResponseRead]],
    summary="Réponses de recruteurs reçues",
    responses=error_responses(401),
)
def list_responses(
    user: CurrentUser,
    service: Responses,
    pagination: PaginationParams = Depends(),
    application_id: uuid.UUID | None = None,
):
    items, total = service.list_responses(user, pagination, application_id)
    return ok(build_page(items, total, pagination))


@router.post(
    "/responses",
    response_model=ApiResponse[RecruiterResponseRead],
    status_code=status.HTTP_201_CREATED,
    summary="Enregistrer une réponse de recruteur (saisie manuelle)",
    description="La réponse est associée à une candidature (application_id ou corrélation "
    "automatique) et son type est analysé (entretien, refus, offre...).",
    responses=error_responses(401, 422),
)
def create_response(payload: RecruiterResponseCreate, user: CurrentUser, service: Responses):
    received = service.receive(
        sender_email=str(payload.sender_email),
        sender_name=payload.sender_name,
        subject=payload.subject,
        body=payload.body,
        received_at=payload.received_at,
        application_id=payload.application_id,
        message_id=payload.message_id,
        user=user,
    )
    return ok(received.response)


@router.patch(
    "/responses/{response_id}",
    response_model=ApiResponse[RecruiterResponseRead],
    summary="Associer une réponse à une candidature / la marquer comme lue",
    responses=error_responses(401, 404, 422),
)
def update_response(
    response_id: uuid.UUID, payload: RecruiterResponseUpdate, user: CurrentUser, service: Responses
):
    return ok(service.update(user, response_id, payload))


# --- Candidatures ---


@router.post(
    "",
    response_model=ApiResponse[ApplicationRead],
    status_code=status.HTTP_201_CREATED,
    summary="Créer une candidature",
    description="Une seule candidature active par offre (RG-10). Statut initial : not_applied ou preparing.",
    responses=error_responses(401, 404, 409, 422),
)
def create_application(payload: ApplicationCreate, user: CurrentUser, service: Service):
    return ok(service.create(user, payload))


@router.get(
    "",
    response_model=ApiResponse[Page[ApplicationRead]],
    summary="Mes candidatures",
    responses=error_responses(401),
)
def list_applications(
    user: CurrentUser,
    service: Service,
    pagination: PaginationParams = Depends(),
    status_filter: ApplicationStatus | None = None,
    job_id: uuid.UUID | None = None,
):
    items, total = service.list_applications(user, pagination, status_filter, job_id)
    return ok(build_page(items, total, pagination))


@router.get(
    "/{application_id}",
    response_model=ApiResponse[ApplicationRead],
    summary="Détail d'une candidature",
    responses=error_responses(401, 404),
)
def get_application(application_id: uuid.UUID, user: CurrentUser, service: Service):
    return ok(service.get(user, application_id))


@router.put(
    "/{application_id}",
    response_model=ApiResponse[ApplicationRead],
    summary="Modifier une candidature (CV, lettre, email, notes...)",
    description="Mise à jour partielle. Le statut se change avec PATCH /status.",
    responses=error_responses(401, 404, 422),
)
def update_application(
    application_id: uuid.UUID, payload: ApplicationUpdate, user: CurrentUser, service: Service
):
    return ok(service.update(user, application_id, payload))


@router.delete(
    "/{application_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Supprimer une candidature non envoyée",
    responses=error_responses(401, 404, 422),
)
def delete_application(application_id: uuid.UUID, user: CurrentUser, service: Service) -> None:
    service.delete(user, application_id)


@router.patch(
    "/{application_id}/status",
    response_model=ApiResponse[ApplicationRead],
    summary="Changer le statut",
    description="Respecte le cycle NOT_APPLIED -> PREPARING -> READY -> SUBMITTED -> FOLLOW_UP -> "
    "INTERVIEW -> OFFER (REJECTED / WITHDRAWN terminaux). SUBMITTED n'est possible que via "
    "POST /submit (confirmation explicite).",
    responses=error_responses(401, 404, 422),
)
def change_status(
    application_id: uuid.UUID, payload: StatusChange, user: CurrentUser, service: Service
):
    return ok(service.change_status_for_user(user, application_id, payload.status, payload.note))


@router.post(
    "/{application_id}/prepare",
    response_model=ApiResponse[ApplicationRead],
    summary="Préparer la candidature (brouillons + CV) -> READY",
    description="Génère la lettre et l'email (IA si configurée, sinon modèles), choisit le CV le "
    "plus adapté, puis passe la candidature à READY. Rien n'est envoyé.",
    responses=error_responses(401, 404, 422),
)
def prepare_application(
    application_id: uuid.UUID, payload: PrepareRequest, user: CurrentUser, service: Service
):
    return ok(service.prepare(user, application_id, payload))


@router.post(
    "/{application_id}/generate",
    response_model=ApiResponse[GeneratedText],
    summary="Générer un texte (lettre, email, résumé, réponse recruteur)",
    responses=error_responses(401, 404, 422),
)
def generate_text(
    application_id: uuid.UUID, payload: GenerateRequest, user: CurrentUser, service: Service
):
    return ok(service.generate(user, application_id, payload))


@router.post(
    "/{application_id}/submit",
    response_model=ApiResponse[ApplicationRead],
    summary="Valider l'envoi (confirmation explicite obligatoire)",
    description="Uniquement depuis READY, avec `confirm=true`. `send_email=true` envoie l'email "
    "de candidature avec le CV en pièce jointe ; sinon la candidature est simplement marquée "
    "envoyée (ex : formulaire du site). Une candidature n'est jamais envoyée automatiquement.",
    responses=error_responses(401, 404, 409, 422, 502),
)
def submit_application(
    application_id: uuid.UUID, payload: SubmitRequest, user: CurrentUser, service: Service
):
    return ok(service.submit(user, application_id, payload))


@router.get(
    "/{application_id}/history",
    response_model=ApiResponse[list[StatusHistoryRead]],
    summary="Historique des statuts",
    responses=error_responses(401, 404),
)
def get_history(application_id: uuid.UUID, user: CurrentUser, service: Service):
    return ok(service.get_history(user, application_id))
