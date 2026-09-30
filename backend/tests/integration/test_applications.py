from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.modules.integrations.email.service import EmailService
from tests.factories import API, create_job, pdf_bytes, setup_candidate


def create_application(
    client: TestClient, headers: dict[str, str], job_id: str, **extra: Any
) -> dict[str, Any]:
    response = client.post(f"{API}/applications", headers=headers, json={"job_id": job_id, **extra})
    assert response.status_code == 201, response.text
    return response.json()["data"]


def set_status(client: TestClient, headers: dict[str, str], application_id: str, status: str):  # type: ignore[no-untyped-def]
    return client.patch(
        f"{API}/applications/{application_id}/status", headers=headers, json={"status": status}
    )


def test_create_application_snapshots_job(client: TestClient, user_headers: dict[str, str]) -> None:
    job = create_job(client, user_headers)
    application = create_application(client, user_headers, job["id"])
    assert application["status"] == "not_applied"
    assert application["job_title"] == job["title"]
    assert application["company_name"] == "Exemple SAS"
    assert application["job"]["id"] == job["id"]
    listed = client.get(f"{API}/jobs/{job['id']}", headers=user_headers).json()["data"]["status"]
    assert listed["application_id"] == application["id"]


def test_one_active_application_per_job(
    client: TestClient, user_headers: dict[str, str], admin_headers: dict[str, str]
) -> None:
    job = create_job(client, user_headers)
    first = create_application(client, user_headers, job["id"])
    duplicate = client.post(f"{API}/applications", headers=user_headers, json={"job_id": job["id"]})
    assert duplicate.status_code == 409
    assert duplicate.json()["error"]["code"] == "APPLICATION_ALREADY_EXISTS"
    # Un autre utilisateur peut postuler à la même offre.
    create_application(client, admin_headers, job["id"])
    # Après un retrait, une nouvelle candidature est possible.
    assert set_status(client, user_headers, first["id"], "withdrawn").status_code == 200
    create_application(client, user_headers, job["id"])


def test_application_without_job_needs_title(
    client: TestClient, user_headers: dict[str, str]
) -> None:
    assert client.post(f"{API}/applications", headers=user_headers, json={}).status_code == 422
    manual = client.post(
        f"{API}/applications",
        headers=user_headers,
        json={"job_title": "Candidature spontanée", "company_name": "ACME"},
    )
    assert manual.status_code == 201


def test_status_machine_is_enforced(client: TestClient, user_headers: dict[str, str]) -> None:
    job = create_job(client, user_headers)
    application = create_application(client, user_headers, job["id"])
    invalid = set_status(client, user_headers, application["id"], "interview")
    assert invalid.status_code == 422
    assert invalid.json()["error"]["code"] == "INVALID_STATUS_TRANSITION"
    assert "preparing" in invalid.json()["error"]["details"]["allowed"]

    assert set_status(client, user_headers, application["id"], "preparing").status_code == 200
    assert set_status(client, user_headers, application["id"], "ready").status_code == 200
    forbidden = set_status(client, user_headers, application["id"], "submitted")
    assert forbidden.json()["error"]["code"] == "SUBMIT_REQUIRES_CONFIRMATION"


def test_submit_requires_explicit_confirmation(
    client: TestClient, user_headers: dict[str, str]
) -> None:
    job = create_job(client, user_headers)
    application = create_application(client, user_headers, job["id"], status="preparing")
    url = f"{API}/applications/{application['id']}/submit"
    assert (
        client.post(url, headers=user_headers, json={"confirm": True}).json()["error"]["code"]
        == "APPLICATION_NOT_READY"
    )
    set_status(client, user_headers, application["id"], "ready")
    assert (
        client.post(url, headers=user_headers, json={"confirm": False}).json()["error"]["code"]
        == "CONFIRMATION_REQUIRED"
    )

    submitted = client.post(url, headers=user_headers, json={"confirm": True, "method": "website"})
    assert submitted.status_code == 200, submitted.text
    data = submitted.json()["data"]
    assert data["status"] == "submitted"
    assert data["submitted_at"] and data["follow_up_at"]
    assert data["submission_method"] == "website"
    again = client.post(url, headers=user_headers, json={"confirm": True})
    assert again.status_code == 409

    for status in ("follow_up", "interview", "offer"):
        assert set_status(client, user_headers, application["id"], status).status_code == 200
    history = client.get(
        f"{API}/applications/{application['id']}/history", headers=user_headers
    ).json()["data"]
    assert [entry["to_status"] for entry in history] == [
        "preparing", "ready", "submitted", "follow_up", "interview", "offer",
    ]  # fmt: skip
    assert (
        client.delete(f"{API}/applications/{application['id']}", headers=user_headers).status_code
        == 204
    )


def test_prepare_generates_drafts_and_selects_cv(
    client: TestClient, user_headers: dict[str, str]
) -> None:
    setup_candidate(client, user_headers)
    cv = client.post(
        f"{API}/documents", headers=user_headers,
        files={"file": ("cv.pdf", pdf_bytes(), "application/pdf")}, data={"document_type": "cv", "language": "fr"},
    ).json()["data"]  # fmt: skip
    job = create_job(client, user_headers)
    application = create_application(client, user_headers, job["id"])
    prepared = client.post(
        f"{API}/applications/{application['id']}/prepare",
        headers=user_headers,
        json={"language": "fr"},
    )
    assert prepared.status_code == 200, prepared.text
    data = prepared.json()["data"]
    assert data["status"] == "ready"
    assert data["cv_document_id"] == cv["id"]
    assert "Exemple SAS" in data["cover_letter_text"]
    assert data["email_subject"].startswith("Candidature")
    notifications = client.get(
        f"{API}/notifications?type=application_status", headers=user_headers
    ).json()["data"]
    assert notifications["items"][0]["data"]["status"] == "ready"


def test_generate_texts_without_ai(client: TestClient, user_headers: dict[str, str]) -> None:
    job = create_job(client, user_headers)
    application = create_application(client, user_headers, job["id"])
    url = f"{API}/applications/{application['id']}/generate"
    summary = client.post(
        url, headers=user_headers, json={"kind": "job_summary", "save": False}
    ).json()["data"]
    assert summary["generated_by"] == "rules" and summary["content"]
    letter = client.post(url, headers=user_headers, json={"kind": "cover_letter"}).json()["data"]
    assert letter["kind"] == "cover_letter"
    stored = client.get(f"{API}/applications/{application['id']}", headers=user_headers).json()[
        "data"
    ]
    assert stored["cover_letter_text"] == letter["content"]
    missing = client.post(url, headers=user_headers, json={"kind": "recruiter_reply"})
    assert missing.json()["error"]["code"] == "RESPONSE_REQUIRED"


def test_submit_by_email_sends_cv(
    client: TestClient, user_headers: dict[str, str], monkeypatch: pytest.MonkeyPatch
) -> None:
    sent: list[dict[str, Any]] = []

    def fake_send(self: EmailService, to: str, subject: str, text_body: str, html_body=None, attachments=None, reply_to=None) -> str:  # type: ignore[no-untyped-def]
        sent.append(
            {"to": to, "subject": subject, "attachments": attachments, "reply_to": reply_to}
        )
        return "<message-id@test>"

    monkeypatch.setattr(EmailService, "send_email", fake_send)
    monkeypatch.setattr(EmailService, "is_configured", property(lambda self: True))
    client.post(
        f"{API}/documents",
        headers=user_headers,
        files={"file": ("cv.pdf", pdf_bytes(), "application/pdf")},
        data={"document_type": "cv"},
    )
    job = create_job(client, user_headers, application={"email": "rh@example.com", "url": None})
    application = create_application(client, user_headers, job["id"])
    client.post(f"{API}/applications/{application['id']}/prepare", headers=user_headers, json={})
    response = client.post(
        f"{API}/applications/{application['id']}/submit",
        headers=user_headers,
        json={"confirm": True, "send_email": True},
    )
    assert response.status_code == 200, response.text
    assert response.json()["data"]["submission_method"] == "email"
    assert response.json()["data"]["submission_reference"] == "<message-id@test>"
    assert sent[0]["to"] == "rh@example.com"
    assert sent[0]["attachments"][0].content == pdf_bytes()


def test_recruiter_response_is_correlated_and_classified(
    client: TestClient, user_headers: dict[str, str]
) -> None:
    job = create_job(
        client, user_headers, recruiter={"name": "Alex", "email": "alex@exemple-rh.example"}
    )
    application = create_application(client, user_headers, job["id"])
    response = client.post(
        f"{API}/applications/responses", headers=user_headers,
        json={
            "sender_email": "alex@exemple-rh.example",
            "subject": "Votre candidature",
            "body": "Bonjour, nous souhaitons vous rencontrer pour un entretien. Quelles sont vos disponibilités ?",
            "message_id": "<m1@example>",
        },
    )  # fmt: skip
    assert response.status_code == 201, response.text
    data = response.json()["data"]
    assert data["application_id"] == application["id"]
    assert data["correlation_method"] == "recruiter_email"
    assert data["response_type"] == "interview"
    assert data["analysis"]["suggested_status"] == "interview"
    # Le statut n'est pas modifié automatiquement : c'est une suggestion.
    stored = client.get(f"{API}/applications/{application['id']}", headers=user_headers).json()[
        "data"
    ]
    assert stored["status"] == "not_applied" and stored["response_received_at"]
    listed = client.get(
        f"{API}/applications/responses?application_id={application['id']}", headers=user_headers
    ).json()["data"]
    assert listed["pagination"]["total"] == 1


def test_users_cannot_access_others_applications(
    client: TestClient, user_headers: dict[str, str], admin_headers: dict[str, str]
) -> None:
    job = create_job(client, user_headers)
    application = create_application(client, user_headers, job["id"])
    assert (
        client.get(f"{API}/applications/{application['id']}", headers=admin_headers).status_code
        == 404
    )
    assert set_status(client, admin_headers, application["id"], "preparing").status_code == 404
