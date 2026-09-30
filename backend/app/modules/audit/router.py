import uuid

from fastapi import APIRouter, Depends, Query

from app.api.dependencies import DbSession, SuperUser
from app.modules.audit.schemas import AuditLogRead
from app.modules.audit.service import AuditService
from app.shared.pagination import Page, PaginationParams, build_page
from app.shared.schemas import ApiResponse, error_responses, ok

router = APIRouter(prefix="/audit-logs", tags=["Audit"])


@router.get(
    "",
    response_model=ApiResponse[Page[AuditLogRead]],
    summary="Journal d'audit (admin)",
    description="Opérations critiques : connexions, changements de statut de candidature, "
    "collectes, webhooks n8n... Le filtre `action` est un préfixe (ex: `application.`).",
    responses=error_responses(401, 403),
)
def list_audit_logs(
    _admin: SuperUser,
    session: DbSession,
    pagination: PaginationParams = Depends(),
    action: str | None = Query(None, max_length=100),
    entity_type: str | None = Query(None, max_length=50),
    entity_id: str | None = Query(None, max_length=64),
    actor_id: uuid.UUID | None = None,
):
    items, total = AuditService(session).search(
        pagination, action=action, entity_type=entity_type, entity_id=entity_id, actor_id=actor_id
    )
    return ok(build_page(items, total, pagination))
