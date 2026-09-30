from typing import Annotated

from fastapi import APIRouter, Depends, Request, status

from app.api.dependencies import CurrentUser, TokenPayload
from app.core.rate_limit import auth_rate_limit
from app.modules.auth.dependencies import get_auth_service
from app.modules.auth.schemas import (
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    RegisterRequest,
    TokenPair,
)
from app.modules.auth.service import AuthService
from app.modules.users.schemas import UserRead
from app.shared.schemas import ApiResponse, MessageData, error_responses, message, ok

router = APIRouter(prefix="/auth", tags=["Auth"])

Service = Annotated[AuthService, Depends(get_auth_service)]


@router.post(
    "/register",
    response_model=ApiResponse[UserRead],
    status_code=status.HTTP_201_CREATED,
    summary="Créer un compte",
    description="Crée un compte. Le premier compte créé devient administrateur (superuser). "
    "Les inscriptions suivantes peuvent être bloquées avec ALLOW_REGISTRATION=false.",
    responses=error_responses(403, 409, 422, 429),
    dependencies=[Depends(auth_rate_limit)],
)
def register(payload: RegisterRequest, service: Service):
    return ok(service.register(payload.email, payload.password))


@router.post(
    "/login",
    response_model=ApiResponse[TokenPair],
    summary="Se connecter",
    description="Retourne un access token (courte durée) et un refresh token (longue durée).",
    responses=error_responses(401, 422, 429),
    dependencies=[Depends(auth_rate_limit)],
)
def login(payload: LoginRequest, request: Request, service: Service):
    user_agent = request.headers.get("user-agent")
    return ok(service.login(payload.email, payload.password, user_agent))


@router.post(
    "/refresh",
    response_model=ApiResponse[TokenPair],
    summary="Renouveler les tokens",
    description="Échange un refresh token valide contre un nouveau couple de tokens. "
    "L'ancien refresh token devient inutilisable (rotation).",
    responses=error_responses(401, 422, 429),
    dependencies=[Depends(auth_rate_limit)],
)
def refresh(payload: RefreshRequest, request: Request, service: Service):
    return ok(service.refresh(payload.refresh_token, request.headers.get("user-agent")))


@router.post(
    "/logout",
    response_model=ApiResponse[MessageData],
    summary="Se déconnecter",
    description="Révoque immédiatement l'access token courant et le refresh token fourni "
    "(ou toutes les sessions avec `all_devices=true`).",
    responses=error_responses(401),
)
def logout(payload: LogoutRequest, user: CurrentUser, token: TokenPayload, service: Service):
    service.logout(user, token, payload.refresh_token, payload.all_devices)
    return message("Logged out")


@router.get(
    "/me",
    response_model=ApiResponse[UserRead],
    summary="Utilisateur connecté",
    responses=error_responses(401),
)
def me(user: CurrentUser):
    return ok(user)
