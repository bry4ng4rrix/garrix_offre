"""Pagination standard des listes.

Deux styles sont acceptés (au choix du client Flutter) :
- `?page=2&page_size=20`
- `?limit=20&offset=20`  (prioritaire si fourni)

Réponse :
    {"items": [...], "pagination": {"total": 100, "page": 2, "page_size": 20, "pages": 5}}
"""

import math
from typing import Any

from fastapi import Query
from pydantic import BaseModel

DEFAULT_PAGE_SIZE = 20
MAX_PAGE_SIZE = 100


class PaginationParams:
    """Dépendance FastAPI : `pagination: PaginationParams = Depends()`."""

    def __init__(
        self,
        page: int = Query(1, ge=1, description="Numéro de page (commence à 1)"),
        page_size: int = Query(
            DEFAULT_PAGE_SIZE, ge=1, le=MAX_PAGE_SIZE, description="Taille de page"
        ),
        limit: int | None = Query(
            None, ge=1, le=MAX_PAGE_SIZE, description="Alternative à page_size"
        ),
        offset: int | None = Query(None, ge=0, description="Alternative à page"),
    ) -> None:
        if limit is not None or offset is not None:
            self.limit = limit or page_size
            self.offset = offset or 0
            self.page = self.offset // self.limit + 1
        else:
            self.limit = page_size
            self.offset = (page - 1) * page_size
            self.page = page

    @classmethod
    def first(cls, size: int = DEFAULT_PAGE_SIZE) -> "PaginationParams":
        """Pratique hors FastAPI (scripts, tests)."""
        return cls(page=1, page_size=size, limit=None, offset=None)


class PaginationMeta(BaseModel):
    total: int
    page: int
    page_size: int
    pages: int


class Page[T](BaseModel):
    items: list[T]
    pagination: PaginationMeta


def build_page(items: list[Any], total: int, params: PaginationParams) -> dict[str, Any]:
    return {
        "items": items,
        "pagination": {
            "total": total,
            "page": params.page,
            "page_size": params.limit,
            "pages": math.ceil(total / params.limit) if total else 0,
        },
    }
