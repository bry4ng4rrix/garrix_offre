"""Repository de base : opérations communes à toutes les tables.

Chaque module crée son repository en héritant de `BaseRepository` :

    class CompanyRepository(BaseRepository[Company]):
        model = Company

        def get_by_name(self, name: str) -> Company | None:
            ...

Le repository ne fait jamais `commit()` : c'est le service qui décide quand valider.
"""

import uuid
from typing import Any

from sqlalchemy import Select, func, select
from sqlalchemy.orm import Session

from app.core.database import Base
from app.shared.pagination import PaginationParams


class BaseRepository[ModelT: Base]:
    model: type[ModelT]

    def __init__(self, session: Session) -> None:
        self.session = session

    def get(self, entity_id: uuid.UUID) -> ModelT | None:
        return self.session.get(self.model, entity_id)

    def add(self, entity: ModelT) -> ModelT:
        self.session.add(entity)
        self.session.flush()
        return entity

    def delete(self, entity: ModelT) -> None:
        self.session.delete(entity)
        self.session.flush()

    def list_all(self, *order_by: Any) -> list[ModelT]:
        return list(self.session.scalars(select(self.model).order_by(*order_by)))

    def paginate(self, stmt: Select[Any], pagination: PaginationParams) -> tuple[list[Any], int]:
        """Exécute `stmt` pour une page donnée et retourne (éléments, total)."""
        count_stmt = select(func.count()).select_from(stmt.order_by(None).subquery())
        total = self.session.scalar(count_stmt) or 0
        items = self.session.scalars(stmt.limit(pagination.limit).offset(pagination.offset))
        return list(items.unique()), total
