"""Fonctions utilitaires pour créer rapidement des données dans les tests."""

from typing import Any

from fastapi.testclient import TestClient

PASSWORD = "Passw0rd!"
N8N_SECRET = "test-n8n-webhook-secret"
API = "/api/v1"


def register_and_login(client: TestClient, email: str, password: str = PASSWORD) -> dict[str, str]:
    response = client.post(f"{API}/auth/register", json={"email": email, "password": password})
    assert response.status_code == 201, response.text
    tokens = client.post(f"{API}/auth/login", json={"email": email, "password": password}).json()[
        "data"
    ]
    return {"Authorization": f"Bearer {tokens['access_token']}"}


def job_payload(**overrides: Any) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "external_id": "job-1",
        "title": "Développeur Full Stack Python / React (H/F)",
        "description": (
            "Nous recherchons un développeur Python, Django et React pour notre équipe produit à Paris. "
            "Vous travaillerez avec les équipes produit. 3 ans d'expérience minimum. "
            "Docker est un plus.\nSalaire : 45 - 55 k€ par an."
        ),
        "url": "https://example.com/jobs/1",
        "company": {"name": "Exemple SAS", "website": "https://example.com"},
        "location": "Paris, France",
        "contract": "CDI",
    }
    payload.update(overrides)
    return payload


def create_job(client: TestClient, headers: dict[str, str], **overrides: Any) -> dict[str, Any]:
    response = client.post(f"{API}/jobs", headers=headers, json=job_payload(**overrides))
    assert response.status_code in (200, 201), response.text
    return response.json()["data"]


def setup_candidate(client: TestClient, headers: dict[str, str]) -> None:
    """Profil + compétences + préférences typiques d'un développeur Python / React à Paris."""
    client.put(
        f"{API}/profile",
        headers=headers,
        json={
            "first_name": "Jane",
            "last_name": "Doe",
            "city": "Paris",
            "country": "France",
            "experience_level": "mid",
            "years_of_experience": 4,
            "languages": [{"code": "fr", "level": "native"}],
        },
    )
    for name in ("Python", "Django", "React", "Docker"):
        client.post(f"{API}/skills", headers=headers, json={"name": name, "level": "advanced"})
    client.put(
        f"{API}/preferences",
        headers=headers,
        json={
            "job_titles": ["Full Stack Developer"],
            "contract_types": ["cdi"],
            "locations": [{"city": "Paris", "country": "France"}],
            "minimum_salary": 40000,
            "salary_period": "year",
            "matching_threshold": 70,
        },
    )


def png_bytes() -> bytes:
    return b"\x89PNG\r\n\x1a\n" + b"\x00" * 64


def pdf_bytes() -> bytes:
    return b"%PDF-1.4\n% test document\n"
