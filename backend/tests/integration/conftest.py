import pytest
from fastapi.testclient import TestClient

from tests.conftest import reset_database
from tests.factories import N8N_SECRET, register_and_login


@pytest.fixture(autouse=True)
def clean_state(database: None):
    """Chaque test d'intégration part d'une base propre (avec les référentiels)."""
    yield
    reset_database()


@pytest.fixture
def admin_headers(client: TestClient) -> dict[str, str]:
    """Premier compte créé = administrateur."""
    return register_and_login(client, "admin@example.com")


@pytest.fixture
def user_headers(client: TestClient, admin_headers: dict[str, str]) -> dict[str, str]:
    """Second compte = utilisateur simple."""
    return register_and_login(client, "user@example.com")


@pytest.fixture
def n8n_headers() -> dict[str, str]:
    return {"X-N8N-Webhook-Secret": N8N_SECRET}
