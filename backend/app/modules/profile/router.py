from typing import Annotated

from fastapi import APIRouter, Depends, File, UploadFile, status
from fastapi.responses import StreamingResponse

from app.api.dependencies import CurrentUser
from app.modules.documents.router import file_response
from app.modules.profile.dependencies import get_profile_service
from app.modules.profile.schemas import ProfileRead, ProfileUpdate
from app.modules.profile.service import ProfileService
from app.shared.schemas import ApiResponse, error_responses, ok

router = APIRouter(prefix="/profile", tags=["Profile"])

Service = Annotated[ProfileService, Depends(get_profile_service)]


@router.get(
    "",
    response_model=ApiResponse[ProfileRead],
    summary="Mon profil professionnel",
    responses=error_responses(401),
)
def get_profile(user: CurrentUser, service: Service):
    return ok(service.get_profile(user))


@router.put(
    "",
    response_model=ApiResponse[ProfileRead],
    summary="Modifier mon profil",
    description="Mise à jour partielle : seuls les champs envoyés sont modifiés. "
    "`minimum_salary`, `currency`, `salary_period` et `remote` sont partagés avec /preferences.",
    responses=error_responses(401, 422),
)
def update_profile(payload: ProfileUpdate, user: CurrentUser, service: Service):
    return ok(service.update_profile(user, payload))


@router.post(
    "/photo",
    response_model=ApiResponse[ProfileRead],
    summary="Envoyer ma photo de profil",
    description="Upload multipart (jpg, png, webp). Remplace la photo précédente.",
    responses=error_responses(401, 413, 422),
)
def upload_photo(
    user: CurrentUser, service: Service, file: UploadFile = File(..., description="Image")
):
    return ok(service.upload_photo(user, file))


@router.get(
    "/photo",
    summary="Télécharger ma photo de profil",
    response_class=StreamingResponse,
    responses={200: {"content": {"image/jpeg": {}, "image/png": {}}}, **error_responses(401, 404)},
)
def get_photo(user: CurrentUser, service: Service) -> StreamingResponse:
    document, chunks = service.stream_photo(user)
    return file_response(document, chunks, inline=True)


@router.delete(
    "/photo",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Supprimer ma photo de profil",
    responses=error_responses(401, 404),
)
def delete_photo(user: CurrentUser, service: Service) -> None:
    service.delete_photo(user)
