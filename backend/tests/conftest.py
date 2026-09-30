"""Configuration commune des tests.

Les tests d'intégration utilisent un vrai PostgreSQL et un vrai Redis, ceux de Docker Compose :

    docker compose up -d postgres redis
    make test

- base de test : <nom de la base>_test (créée si besoin, schéma recréé par les migrations Alembic) ;
- Redis : base n°15 (vidée entre chaque test) ;
- Celery : mode "eager" (les tâches s'exécutent immédiatement, dans le test) ;
- Telegram / SMTP / IA : désactivés.

TEST_DATABASE_URL et TEST_REDIS_URL permettent de pointer ailleurs.
"""

import os
import tempfile
from pathlib import Path

from dotenv import dotenv_values
from sqlalchemy.engine import make_url

ROOT = Path(__file__).resolve().parent.parent
_ENV_FILE = dotenv_values(ROOT / ".env")


def _test_database_url() -> str:
    if os.environ.get("TEST_DATABASE_URL"):
        return os.environ["TEST_DATABASE_URL"]
    base = os.environ.get("DATABASE_URL") or _ENV_FILE.get("DATABASE_URL")
    url = make_url(base or "postgresql+psycopg://garrix:garrix@localhost:5433/garrix_offre")
    return url.set(database=f"{url.database}_test").render_as_string(hide_password=False)


def _test_redis_url() -> str:
    if os.environ.get("TEST_REDIS_URL"):
        return os.environ["TEST_REDIS_URL"]
    base = os.environ.get("REDIS_URL") or _ENV_FILE.get("REDIS_URL") or "redis://localhost:6380/0"
    return base.rsplit("/", 1)[0] + "/15"


# Doit être fait AVANT tout import de l'application (la configuration est lue une seule fois).
os.environ.update(
    {
        "APP_ENV": "test",
        "DATABASE_URL": _test_database_url(),
        "REDIS_URL": _test_redis_url(),
        "CELERY_BROKER_URL": _test_redis_url(),
        "CELERY_TASK_ALWAYS_EAGER": "true",
        "RATE_LIMIT_ENABLED": "false",
        "LOG_LEVEL": "WARNING",
        "LOG_FORMAT": "console",
        "STORAGE_PATH": tempfile.mkdtemp(prefix="garrix-tests-"),
        "JWT_SECRET_KEY": "test-jwt-secret-key-with-more-than-32-characters",
        "N8N_WEBHOOK_SECRET": "test-n8n-webhook-secret",
        "N8N_BASE_URL": "http://127.0.0.1:9",
        "NOTIFICATION_DELIVERY_MODE": "backend",
        "ALLOW_REGISTRATION": "true",
        "ALLOW_PRIVATE_SOURCE_URLS": "true",
        "AI_PROVIDER": "none",
        "TELEGRAM_BOT_TOKEN": "",
        "TELEGRAM_CHAT_ID": "",
        "SMTP_HOST": "",
        "SMTP_FROM": "",
        "SCRAPER_DEFAULT_RATE_LIMIT": "600",
    }
)

import psycopg  # noqa: E402
import pytest  # noqa: E402
from alembic import command  # noqa: E402
from alembic.config import Config  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import text  # noqa: E402
from sqlalchemy.orm import Session  # noqa: E402

from app.core.database import Base, SessionLocal, engine  # noqa: E402
from app.core.redis import get_redis  # noqa: E402


def _ensure_database_exists(url: str) -> None:
    parsed = make_url(url)
    admin_url = parsed.set(drivername="postgresql", database="postgres").render_as_string(
        hide_password=False
    )
    with psycopg.connect(admin_url, autocommit=True) as connection:
        exists = connection.execute(
            "SELECT 1 FROM pg_database WHERE datname = %s", (parsed.database,)
        ).fetchone()
        if not exists:
            connection.execute(f'CREATE DATABASE "{parsed.database}"')
        # Base de test uniquement : commits non synchrones (beaucoup plus rapides, sans risque ici).
        connection.execute(f'ALTER DATABASE "{parsed.database}" SET synchronous_commit = off')


@pytest.fixture(scope="session")
def database() -> None:
    """Recrée le schéma de la base de test avec les migrations Alembic."""
    url = os.environ["DATABASE_URL"]
    _ensure_database_exists(url)
    engine.dispose()  # les nouvelles connexions prennent en compte synchronous_commit
    with engine.begin() as connection:
        connection.execute(text("DROP SCHEMA public CASCADE"))
        connection.execute(text("CREATE SCHEMA public"))
    config = Config(str(ROOT / "alembic.ini"))
    config.set_main_option("sqlalchemy.url", url.replace("%", "%%"))
    command.upgrade(config, "head")
    reset_database()


def reset_database() -> None:
    """Vide toutes les tables puis recharge les données de référence."""
    from scripts.seed import seed_reference_data

    # DELETE (tables enfants d'abord) : beaucoup plus rapide que TRUNCATE sur des tables presque vides.
    with engine.begin() as connection:
        for table in reversed(Base.metadata.sorted_tables):
            connection.execute(table.delete())
    with SessionLocal() as session:
        seed_reference_data(session)
    get_redis().flushdb()


@pytest.fixture(scope="session")
def client(database: None) -> TestClient:
    from app.main import app

    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def db(database: None) -> Session:
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()
