"""Trois groupes d'endpoints liés à l'expérience :

- /experiences             : parcours professionnel (postes occupés)
- /experience-preferences  : technologies / expériences recherchées dans les offres
- /experience-levels       : référentiel des niveaux (junior, senior...)
"""

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, status

from app.api.dependencies import CurrentUser, SuperUser
from app.modules.experiences.dependencies import (
    get_experience_level_service,
    get_experience_preference_service,
    get_experience_service,
)
from app.modules.experiences.schemas import (
    ExperienceCreate,
    ExperienceLevelCreate,
    ExperienceLevelRead,
    ExperienceLevelUpdate,
    ExperiencePreferenceCreate,
    ExperiencePreferenceRead,
    ExperiencePreferenceUpdate,
    ExperienceRead,
    ExperienceUpdate,
)
from app.modules.experiences.service import (
    ExperienceLevelService,
    ExperiencePreferenceService,
    ExperienceService,
)
from app.shared.schemas import ApiResponse, error_responses, ok

router = APIRouter(tags=["Experiences"])

Experiences = Annotated[ExperienceService, Depends(get_experience_service)]
Preferences = Annotated[ExperiencePreferenceService, Depends(get_experience_preference_service)]
Levels = Annotated[ExperienceLevelService, Depends(get_experience_level_service)]


# --- Parcours professionnel ---


@router.get(
    "/experiences",
    response_model=ApiResponse[list[ExperienceRead]],
    summary="Mon parcours professionnel",
    responses=error_responses(401),
)
def list_experiences(user: CurrentUser, service: Experiences):
    return ok(service.list_experiences(user))


@router.post(
    "/experiences",
    response_model=ApiResponse[ExperienceRead],
    status_code=status.HTTP_201_CREATED,
    summary="Ajouter une expérience",
    responses=error_responses(401, 422),
)
def create_experience(payload: ExperienceCreate, user: CurrentUser, service: Experiences):
    return ok(service.create(user, payload))


@router.get(
    "/experiences/{experience_id}",
    response_model=ApiResponse[ExperienceRead],
    summary="Détail d'une expérience",
    responses=error_responses(401, 404),
)
def get_experience(experience_id: uuid.UUID, user: CurrentUser, service: Experiences):
    return ok(service.get(user, experience_id))


@router.put(
    "/experiences/{experience_id}",
    response_model=ApiResponse[ExperienceRead],
    summary="Modifier une expérience",
    responses=error_responses(401, 404, 422),
)
def update_experience(
    experience_id: uuid.UUID, payload: ExperienceUpdate, user: CurrentUser, service: Experiences
):
    return ok(service.update(user, experience_id, payload))


@router.delete(
    "/experiences/{experience_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Supprimer une expérience",
    responses=error_responses(401, 404),
)
def delete_experience(experience_id: uuid.UUID, user: CurrentUser, service: Experiences) -> None:
    service.delete(user, experience_id)


# --- Technologies / expériences recherchées ---


@router.get(
    "/experience-preferences",
    response_model=ApiResponse[list[ExperiencePreferenceRead]],
    summary="Technologies recherchées",
    responses=error_responses(401),
)
def list_experience_preferences(
    user: CurrentUser, service: Preferences, enabled_only: bool = False
):
    return ok(service.list_preferences(user, enabled_only))


@router.get(
    "/experience-preferences/grouped",
    response_model=ApiResponse[dict[str, list[ExperiencePreferenceRead]]],
    summary="Technologies recherchées, groupées par catégorie",
    description='Exemple : {"frontend": [React, Next.js], "backend": [Python, Django]}',
    responses=error_responses(401),
)
def grouped_experience_preferences(user: CurrentUser, service: Preferences):
    return ok(service.grouped_by_category(user))


@router.post(
    "/experience-preferences",
    response_model=ApiResponse[ExperiencePreferenceRead],
    status_code=status.HTTP_201_CREATED,
    summary="Ajouter une technologie recherchée",
    responses=error_responses(401, 409, 422),
)
def create_experience_preference(
    payload: ExperiencePreferenceCreate, user: CurrentUser, service: Preferences
):
    return ok(service.create(user, payload))


@router.get(
    "/experience-preferences/{preference_id}",
    response_model=ApiResponse[ExperiencePreferenceRead],
    summary="Détail d'une technologie recherchée",
    responses=error_responses(401, 404),
)
def get_experience_preference(preference_id: uuid.UUID, user: CurrentUser, service: Preferences):
    return ok(service.get(user, preference_id))


@router.put(
    "/experience-preferences/{preference_id}",
    response_model=ApiResponse[ExperiencePreferenceRead],
    summary="Modifier une technologie recherchée",
    responses=error_responses(401, 404, 422),
)
def update_experience_preference(
    preference_id: uuid.UUID,
    payload: ExperiencePreferenceUpdate,
    user: CurrentUser,
    service: Preferences,
):
    return ok(service.update(user, preference_id, payload))


@router.delete(
    "/experience-preferences/{preference_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Supprimer une technologie recherchée",
    responses=error_responses(401, 404),
)
def delete_experience_preference(
    preference_id: uuid.UUID, user: CurrentUser, service: Preferences
) -> None:
    service.delete(user, preference_id)


# --- Niveaux d'expérience (référentiel) ---


@router.get(
    "/experience-levels",
    response_model=ApiResponse[list[ExperienceLevelRead]],
    summary="Lister les niveaux d'expérience",
    responses=error_responses(401),
)
def list_experience_levels(_user: CurrentUser, service: Levels):
    return ok(service.list_levels())


@router.post(
    "/experience-levels",
    response_model=ApiResponse[ExperienceLevelRead],
    status_code=status.HTTP_201_CREATED,
    summary="Créer un niveau (admin)",
    responses=error_responses(401, 403, 409, 422),
)
def create_experience_level(payload: ExperienceLevelCreate, _admin: SuperUser, service: Levels):
    return ok(service.create(payload))


@router.put(
    "/experience-levels/{level_id}",
    response_model=ApiResponse[ExperienceLevelRead],
    summary="Modifier un niveau (admin)",
    responses=error_responses(401, 403, 404, 422),
)
def update_experience_level(
    level_id: uuid.UUID, payload: ExperienceLevelUpdate, _admin: SuperUser, service: Levels
):
    return ok(service.update(level_id, payload))


@router.delete(
    "/experience-levels/{level_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Supprimer un niveau (admin)",
    responses=error_responses(401, 403, 404),
)
def delete_experience_level(level_id: uuid.UUID, _admin: SuperUser, service: Levels) -> None:
    service.delete(level_id)
