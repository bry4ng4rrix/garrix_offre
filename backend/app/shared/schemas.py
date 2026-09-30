"""Schémas communs : format de réponse standard de l'API.

Succès :   {"success": true, "data": {...}}
Erreur :   {"success": false, "error": {"code": "...", "message": "..."}}
Liste :    {"success": true, "data": {"items": [...], "pagination": {...}}}

Dans un router :

    @router.get("/{job_id}", response_model=ApiResponse[JobRead])
    def get_job(...):
        return ok(service.get_job(job_id))
"""

from typing import Any

from pydantic import BaseModel, ConfigDict


class ORMModel(BaseModel):
    """Base des schémas de sortie : lit directement les attributs des modèles SQLAlchemy."""

    model_config = ConfigDict(from_attributes=True)


class ApiResponse[T](BaseModel):
    success: bool = True
    data: T


class ErrorDetail(BaseModel):
    code: str
    message: str
    details: Any | None = None


class ErrorResponse(BaseModel):
    success: bool = False
    error: ErrorDetail

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {"success": False, "error": {"code": "JOB_NOT_FOUND", "message": "Job not found"}}
            ]
        }
    )


class MessageData(BaseModel):
    message: str


def ok(data: Any) -> dict[str, Any]:
    """Enveloppe une donnée dans le format de succès standard."""
    return {"success": True, "data": data}


def message(text: str) -> dict[str, Any]:
    return ok({"message": text})


_ERROR_DESCRIPTIONS = {
    400: "Requête invalide",
    401: "Non authentifié (token manquant, invalide ou expiré)",
    403: "Accès refusé",
    404: "Ressource introuvable",
    409: "Conflit (la ressource existe déjà)",
    413: "Body ou fichier trop volumineux",
    422: "Données invalides ou règle métier non respectée",
    429: "Trop de requêtes",
    502: "Service externe en erreur",
    503: "Service indisponible",
}


def error_responses(*status_codes: int) -> dict[int | str, dict[str, Any]]:
    """Documente les erreurs possibles d'un endpoint dans OpenAPI."""
    return {
        code: {"model": ErrorResponse, "description": _ERROR_DESCRIPTIONS.get(code, "Erreur")}
        for code in status_codes
    }
