import logging
import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, status
from fastapi.responses import JSONResponse

from app.api.dependencies import CurrentUser
from app.modules.matching.dependencies import get_matching_service
from app.modules.matching.schemas import (
    MatchingSettingsRead,
    MatchingSettingsUpdate,
    MatchResultRead,
    RecalculateResult,
)
from app.modules.matching.service import MatchingService
from app.shared.schemas import ApiResponse, error_responses, ok

router = APIRouter(tags=["Matching"])
logger = logging.getLogger("app.matching")

Service = Annotated[MatchingService, Depends(get_matching_service)]


@router.post(
    "/jobs/{job_id}/match",
    response_model=ApiResponse[MatchResultRead],
    summary="Calculer le matching d'une offre",
    description="Compare l'offre à votre profil et vos préférences, enregistre et retourne "
    "le score (0-100), les compétences correspondantes/manquantes et les raisons.",
    responses=error_responses(401, 404),
)
def match_job(job_id: uuid.UUID, user: CurrentUser, service: Service):
    return ok(service.match_job(user, job_id))


@router.post(
    "/matching/recalculate",
    response_model=ApiResponse[RecalculateResult],
    status_code=status.HTTP_202_ACCEPTED,
    summary="Recalculer tous mes scores",
    description="À appeler après une modification du profil ou des préférences. Par défaut le "
    "calcul tourne en tâche de fond (un événement WebSocket `matching_recalculated` est envoyé "
    "à la fin) ; `background=false` calcule immédiatement.",
    responses=error_responses(401),
)
def recalculate(user: CurrentUser, service: Service, background: bool = True):
    if background:
        from app.modules.matching.tasks import recalculate_user_matches

        try:
            recalculate_user_matches.delay(str(user.id))
            return ok({"status": "queued", "jobs_matched": None})
        except Exception as exc:  # noqa: BLE001 - broker indisponible : calcul direct
            logger.warning("Matching task not queued, running inline: %s", type(exc).__name__)
    count = service.recalculate_for_user(user.id)
    return JSONResponse(status_code=200, content=ok({"status": "done", "jobs_matched": count}))


@router.get(
    "/matching/settings",
    response_model=ApiResponse[MatchingSettingsRead],
    summary="Poids du matching",
    responses=error_responses(401),
)
def get_settings(user: CurrentUser, service: Service):
    return ok(service.get_settings(user))


@router.put(
    "/matching/settings",
    response_model=ApiResponse[MatchingSettingsRead],
    summary="Modifier les poids du matching",
    description="Poids relatifs de 0 à 100 (0 = critère ignoré). Le seuil d'alerte "
    "(`matching_threshold`) se règle dans PUT /preferences.",
    responses=error_responses(401, 422),
)
def update_settings(payload: MatchingSettingsUpdate, user: CurrentUser, service: Service):
    return ok(service.update_settings(user, payload))


@router.post(
    "/matching/settings/reset",
    response_model=ApiResponse[MatchingSettingsRead],
    summary="Réinitialiser les poids (valeurs du .env)",
    responses=error_responses(401),
)
def reset_settings(user: CurrentUser, service: Service):
    return ok(service.reset_settings(user))
