"""Applique les migrations en attente puis charge les données de référence.

Usage : python -m scripts.migrate   (utilisé par le service "migrate" de Docker Compose)

Sécurité : une migration qui supprime des données (DROP TABLE, suppression de colonne...)
n'est JAMAIS appliquée automatiquement. Pour l'appliquer volontairement, après sauvegarde :

    ALLOW_DESTRUCTIVE_MIGRATIONS=true python -m scripts.migrate
"""

import inspect
import logging
import os
import sys
from pathlib import Path

from alembic import command
from alembic.config import Config
from alembic.runtime.migration import MigrationContext
from alembic.script import Script, ScriptDirectory

from app.core.config import get_settings
from app.core.database import engine
from app.core.logging import setup_logging

ROOT = Path(__file__).resolve().parent.parent
logger = logging.getLogger("app.migrations")

DESTRUCTIVE_MARKERS = (
    "op.drop_table",
    "op.drop_column",
    "DROP TABLE",
    "DROP COLUMN",
    "TRUNCATE",
    "DELETE FROM",
)


def alembic_config() -> Config:
    return Config(str(ROOT / "alembic.ini"))


def pending_revisions(config: Config) -> list[Script]:
    scripts = ScriptDirectory.from_config(config)
    with engine.connect() as connection:
        current_heads = MigrationContext.configure(connection).get_current_heads()
    applied: set[str] = set()
    for head in current_heads:
        applied.update(rev.revision for rev in scripts.iterate_revisions(head, "base"))
    return [rev for rev in scripts.walk_revisions("base", "heads") if rev.revision not in applied]


def is_destructive(revision: Script) -> bool:
    module = revision.module
    if getattr(module, "destructive", False):
        return True
    source = inspect.getsource(module.upgrade)
    return any(marker in source for marker in DESTRUCTIVE_MARKERS)


def main() -> int:
    setup_logging(get_settings())
    config = alembic_config()
    pending = pending_revisions(config)
    if not pending:
        logger.info("Database schema is up to date")
    else:
        destructive = [rev.revision for rev in pending if is_destructive(rev)]
        allowed = os.getenv("ALLOW_DESTRUCTIVE_MIGRATIONS", "false").lower() == "true"
        if destructive and not allowed:
            logger.error(
                "Destructive migrations refused. Back up the database, then run with "
                "ALLOW_DESTRUCTIVE_MIGRATIONS=true",
                extra={"revisions": destructive},
            )
            return 1
        logger.info("Applying migrations", extra={"count": len(pending)})
        command.upgrade(config, "head")

    from scripts.seed import seed_reference_data

    seed_reference_data()
    logger.info("Reference data loaded")
    return 0


if __name__ == "__main__":
    sys.exit(main())
