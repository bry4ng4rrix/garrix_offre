"""Connexion PostgreSQL et classes de base des modèles SQLAlchemy.

- `Base` : classe mère de tous les modèles.
- `UUIDPrimaryKeyMixin` / `TimestampMixin` : colonnes communes (id, created_at, updated_at).
- `get_db()` : dépendance FastAPI qui ouvre une session par requête.
- `session_scope()` : même chose pour les scripts et les tâches Celery.

Règle du projet : ce sont les *services* qui appellent `session.commit()`.
Les repositories se contentent de `add()` / `flush()`.
"""

import enum
import logging
import uuid
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, Enum, MetaData, create_engine, func, text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker

from app.core.config import get_settings

# Noms de contraintes stables : indispensable pour qu'Alembic génère des migrations propres.
NAMING_CONVENTION = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_N_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)
    # Les dict/list Python sont stockés en JSONB (PostgreSQL).
    type_annotation_map = {  # noqa: RUF012
        dict[str, Any]: JSONB,
        list[Any]: JSONB,
        list[str]: JSONB,
        list[dict[str, Any]]: JSONB,
        datetime: DateTime(timezone=True),
    }


class UUIDPrimaryKeyMixin:
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)


class TimestampMixin:
    """Dates de création et de modification, toujours en UTC (RG-17)."""

    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now(), onupdate=func.now())


def enum_column(enum_class: type[enum.Enum]) -> Enum:
    """Stocke une énumération Python sous forme de texte (VARCHAR).

    On évite les types ENUM natifs PostgreSQL : ajouter une valeur ne demande
    alors aucune migration.
    """
    return Enum(
        enum_class,
        native_enum=False,
        length=40,
        values_callable=lambda members: [member.value for member in members],
        validate_strings=True,
    )


settings = get_settings()

engine = create_engine(
    settings.DATABASE_URL,
    pool_pre_ping=True,
    pool_size=settings.DATABASE_POOL_SIZE,
    max_overflow=settings.DATABASE_POOL_SIZE,
    echo=settings.DATABASE_ECHO,
)

SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def get_db() -> Iterator[Session]:
    """Dépendance FastAPI : une session par requête, toujours fermée à la fin."""
    session = SessionLocal()
    try:
        yield session
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


def ping_database() -> bool:
    """Vrai si PostgreSQL répond (utilisé par /health, /ready et le monitoring)."""
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
        return True
    except Exception as exc:  # noqa: BLE001 - toute erreur = base indisponible
        logging.getLogger("app.health").warning("Database ping failed: %s", type(exc).__name__)
        return False


@contextmanager
def session_scope() -> Iterator[Session]:
    """Session pour les scripts et tâches Celery (commit à la charge de l'appelant)."""
    session = SessionLocal()
    try:
        yield session
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()
