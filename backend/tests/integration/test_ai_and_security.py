from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.modules.ai.base import AIProvider, AIProviderError, Effort
from app.modules.ai.schemas import GenerationKind
from app.modules.ai.service import AIService
from app.modules.jobs.models import Job
from tests.factories import API, create_job


class FakeProvider(AIProvider):
    name = "fake"
    model = "fake-model"

    def __init__(self, fail: bool = False) -> None:
        self.fail = fail
        self.calls: list[str] = []

    def complete_text(self, system: str, prompt: str, effort: Effort = "medium") -> str:
        self.calls.append(prompt)
        if self.fail:
            raise AIProviderError("down", code="AI_UNREACHABLE")
        return "Texte généré par l'IA"

    def complete_json(
        self, system: str, prompt: str, schema: dict[str, Any], effort: Effort = "low"
    ) -> dict[str, Any]:
        self.calls.append(prompt)
        if self.fail:
            raise AIProviderError("refused", code="AI_REFUSED")
        # Réponse conforme au schéma demandé (tous les champs obligatoires).
        properties = schema["properties"]
        sample: dict[str, Any] = {}
        for name, spec in properties.items():
            if "enum" in spec:
                sample[name] = spec["enum"][0]
            elif spec["type"] == "array":
                sample[name] = ["IA"]
            elif spec["type"] == "integer":
                sample[name] = 2
            else:
                sample[name] = "IA"
        return sample


def test_ai_status_without_provider(client: TestClient, user_headers: dict[str, str]) -> None:
    status = client.get(f"{API}/ai/status", headers=user_headers).json()["data"]
    assert status == {"enabled": False, "provider": "none", "model": None}


def test_job_analysis_without_ai_uses_rules(
    client: TestClient, user_headers: dict[str, str]
) -> None:
    job = create_job(client, user_headers)
    analysis = client.post(f"{API}/ai/jobs/{job['id']}/analyze", headers=user_headers).json()[
        "data"
    ]
    assert analysis["generated_by"] == "rules"
    assert {"Python", "Django", "React"} <= set(analysis["required_skills"])
    assert analysis["preferred_skills"] == ["Docker"]
    assert analysis["min_years_experience"] == 3


def test_ai_provider_is_used_when_available(
    client: TestClient, user_headers: dict[str, str], db: Session
) -> None:
    job_id = create_job(client, user_headers)["id"]
    provider = FakeProvider()
    service = AIService(db, provider=provider)
    analysis = service.analyze_job(db.get(Job, job_id))  # type: ignore[arg-type]
    assert analysis["generated_by"] == "ai"
    assert analysis["summary"] == "IA"
    # Le contenu de l'offre est encadré comme une donnée, pas comme des instructions.
    assert "<job_posting>" in provider.calls[0]
    letter = service.generate_application(
        GenerationKind.COVER_LETTER, {"full_name": "Jane"}, "Dev", "ACME", "desc"
    )
    assert letter == {
        "kind": GenerationKind.COVER_LETTER,
        "subject": None,
        "content": "Texte généré par l'IA",
        "generated_by": "ai",
    }


def test_ai_failure_falls_back_to_rules(db: Session) -> None:
    service = AIService(db, provider=FakeProvider(fail=True))
    response = service.analyze_recruiter_response(
        "Entretien", "Nous souhaitons vous proposer un entretien."
    )
    assert response["generated_by"] == "rules"
    assert response["response_type"] == "interview"
    email = service.generate_application(
        GenerationKind.APPLICATION_EMAIL, {"full_name": "Jane"}, "Dev Python", "ACME", None
    )
    assert email["generated_by"] == "rules"
    assert email["subject"] == "Candidature : Dev Python"


def test_rate_limit_on_login(client: TestClient, monkeypatch: pytest.MonkeyPatch) -> None:
    settings = get_settings()
    monkeypatch.setattr(settings, "RATE_LIMIT_ENABLED", True)
    monkeypatch.setattr(settings, "AUTH_RATE_LIMIT_PER_MINUTE", 3)
    codes = [
        client.post(
            f"{API}/auth/login", json={"email": "x@example.com", "password": "Wrong123!"}
        ).status_code
        for _ in range(5)
    ]
    assert codes[:3] == [401, 401, 401]
    assert codes[3:] == [429, 429]
    blocked = client.post(
        f"{API}/auth/login", json={"email": "x@example.com", "password": "Wrong123!"}
    )
    assert blocked.json()["error"]["code"] == "RATE_LIMITED"
    assert blocked.headers["Retry-After"] == "60"


def test_global_rate_limit_skips_health_and_webhooks(
    client: TestClient, monkeypatch: pytest.MonkeyPatch, n8n_headers: dict[str, str]
) -> None:
    settings = get_settings()
    monkeypatch.setattr(settings, "RATE_LIMIT_ENABLED", True)
    monkeypatch.setattr(settings, "RATE_LIMIT_PER_MINUTE", 2)
    assert [client.get(f"{API}/contract-types").status_code for _ in range(3)] == [401, 401, 429]
    assert client.get("/health").status_code == 200
    assert client.get(f"{API}/webhooks/n8n/sources", headers=n8n_headers).status_code == 200


def test_request_body_size_limit(
    client: TestClient, user_headers: dict[str, str], monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(get_settings(), "MAX_REQUEST_SIZE_MB", 1)
    big = {"notes": "x" * (2 * 1024 * 1024), "job_title": "Test"}
    response = client.post(f"{API}/applications", headers=user_headers, json=big)
    assert response.status_code == 413
    assert response.json()["error"]["code"] == "PAYLOAD_TOO_LARGE"


def test_request_id_and_cors(client: TestClient) -> None:
    response = client.get("/health", headers={"X-Request-ID": "abc-123"})
    assert response.headers["X-Request-ID"] == "abc-123"
    generated = client.get("/health", headers={"X-Request-ID": "invalid id with spaces"})
    assert generated.headers["X-Request-ID"] != "invalid id with spaces"
    preflight = client.options(
        f"{API}/auth/login",
        headers={"Origin": "http://evil.example", "Access-Control-Request-Method": "POST"},
    )
    assert "access-control-allow-origin" not in preflight.headers


def test_openapi_documentation(client: TestClient) -> None:
    spec = client.get("/openapi.json").json()
    assert spec["info"]["title"] == "Garrix Offre API"
    assert "/api/v1/jobs" in spec["paths"]
    assert "/api/v1/webhooks/n8n/jobs" in spec["paths"]
    login = spec["paths"]["/api/v1/auth/login"]["post"]
    assert login["summary"] and "401" in login["responses"]
    assert client.get("/docs").status_code == 200
    assert client.get("/redoc").status_code == 200
