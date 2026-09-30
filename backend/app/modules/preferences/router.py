from typing import Annotated

from fastapi import APIRouter, Depends

from app.api.dependencies import CurrentUser
from app.modules.preferences.dependencies import get_preferences_service
from app.modules.preferences.schemas import PreferencesRead, PreferencesUpdate
from app.modules.preferences.service import PreferencesService
from app.shared.schemas import ApiResponse, error_responses, ok

router = APIRouter(prefix="/preferences", tags=["Preferences"])

Service = Annotated[PreferencesService, Depends(get_preferences_service)]


@router.get(
    "",
    response_model=ApiResponse[PreferencesRead],
    summary="Mes préférences de recherche",
    description="Vue agrégée : postes, contrats, technologies, localisations, télétravail, "
    "salaire minimum, langues et seuil de matching.",
    responses=error_responses(401),
)
def get_preferences(user: CurrentUser, service: Service):
    return ok(service.get_preferences(user))


@router.put(
    "",
    response_model=ApiResponse[PreferencesRead],
    summary="Modifier mes préférences de recherche",
    description="Mise à jour partielle : seuls les champs envoyés sont modifiés. "
    "Pensez à relancer `POST /matching/recalculate` pour mettre à jour les scores.",
    responses=error_responses(401, 422),
)
def update_preferences(payload: PreferencesUpdate, user: CurrentUser, service: Service):
    return ok(service.update_preferences(user, payload))
