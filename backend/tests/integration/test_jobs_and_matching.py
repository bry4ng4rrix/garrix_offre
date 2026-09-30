from fastapi.testclient import TestClient

from tests.factories import API, create_job, job_payload, setup_candidate


def test_created_job_has_normalized_shape(client: TestClient, user_headers: dict[str, str]) -> None:
    job = create_job(client, user_headers)
    assert set(job) >= {
        "id", "title", "source", "company", "recruiter", "location", "contract", "salary", "skills",
        "matching", "application", "status",
    }  # fmt: skip
    assert job["source"]["name"] == "Saisie manuelle"
    assert job["company"]["name"] == "Exemple SAS"
    assert job["company"]["address"] == {
        "street": None,
        "postal_code": None,
        "city": None,
        "country": None,
    }
    assert job["location"] == {
        "raw": "Paris, France",
        "city": "Paris",
        "country": "France",
        "remote": False,
        "hybrid": False,
    }
    assert job["contract"]["type"] == "cdi"
    assert job["salary"] == {
        "min": 45000,
        "max": 55000,
        "currency": "EUR",
        "period": "year",
        "raw": None,
    }
    assert job["experience"] == {"level": "mid", "min_years": 3}
    skills = {skill["name"]: skill["requirement"] for skill in job["skills"]}
    assert skills["Python"] == "required" and skills["Docker"] == "preferred"
    assert job["status"]["application_status"] == "not_applied"
    assert job["application"]["url"] == "https://example.com/jobs/1"


def test_duplicate_jobs_are_merged(client: TestClient, user_headers: dict[str, str]) -> None:
    first = client.post(f"{API}/jobs", headers=user_headers, json=job_payload())
    assert first.status_code == 201
    # Même URL avec paramètres de tracking : même offre.
    same_url = client.post(
        f"{API}/jobs",
        headers=user_headers,
        json=job_payload(external_id=None, url="https://example.com/jobs/1?utm_source=x"),
    )
    assert same_url.status_code == 200
    assert same_url.json()["data"]["id"] == first.json()["data"]["id"]
    # Autre source, même titre / entreprise / ville : empreinte identique.
    other = job_payload(
        external_id="zz", url="https://other-board.example/post/99", company="EXEMPLE"
    )
    fingerprint = client.post(f"{API}/jobs", headers=user_headers, json=other)
    assert fingerprint.json()["data"]["id"] == first.json()["data"]["id"]
    total = client.get(f"{API}/jobs?status=all", headers=user_headers).json()["data"]["pagination"][
        "total"
    ]
    assert total == 1


def test_similar_titles_at_same_company_are_merged(
    client: TestClient, user_headers: dict[str, str]
) -> None:
    first = create_job(client, user_headers, title="Développeur Python Django confirmé")
    second = create_job(
        client,
        user_headers,
        external_id="2",
        url="https://example.com/jobs/2",
        title="Développeur Python / Django confirmé (H/F)",
    )
    assert first["id"] == second["id"]


def test_invalid_job_is_rejected(client: TestClient, user_headers: dict[str, str]) -> None:
    response = client.post(f"{API}/jobs", headers=user_headers, json={"title": "Dev"})
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "INVALID_JOB"


def test_job_filters(client: TestClient, user_headers: dict[str, str]) -> None:
    setup_candidate(client, user_headers)
    create_job(client, user_headers)
    create_job(
        client, user_headers, external_id="remote-1", url="https://example.org/r/1",
        title="Backend Developer Go", description="Remote backend position with Go and Kubernetes. " * 3,
        company="Remote Corp", location="Remote", contract="Freelance", salary="500 € / jour",
    )  # fmt: skip

    def total(query: str) -> int:
        return client.get(f"{API}/jobs?{query}", headers=user_headers).json()["data"]["pagination"][
            "total"
        ]

    assert total("") == 2
    assert total("search=remote corp") == 1
    assert total("contract_type=freelance") == 1
    assert total("remote=true") == 1
    assert total("location=paris") == 1
    assert total("skill=python") == 1
    assert total("company=exemple") == 1
    assert total("experience_level=mid") == 1
    assert total("source=Saisie manuelle") == 2
    assert total("min_score=80") == 1
    assert total("published_after=2999-01-01T00:00:00Z") == 0

    by_score = client.get(f"{API}/jobs?sort_by=score", headers=user_headers).json()["data"]["items"]
    assert by_score[0]["matching"]["score"] >= by_score[1]["matching"]["score"]
    assert by_score[0]["description"] is None and by_score[0]["excerpt"]
    with_description = client.get(
        f"{API}/jobs?include_description=true", headers=user_headers
    ).json()["data"]["items"]
    assert with_description[0]["description"]


def test_pagination_supports_page_and_offset(
    client: TestClient, user_headers: dict[str, str]
) -> None:
    for index in range(5):
        create_job(
            client,
            user_headers,
            external_id=str(index),
            url=f"https://example.com/p/{index}",
            title=f"Poste numéro {index} unique",
            company=f"Société {index}",
        )
    page = client.get(f"{API}/jobs?page=2&page_size=2", headers=user_headers).json()["data"]
    assert page["pagination"] == {"total": 5, "page": 2, "page_size": 2, "pages": 3}
    offset = client.get(f"{API}/jobs?limit=2&offset=4", headers=user_headers).json()["data"]
    assert offset["pagination"]["page"] == 3 and len(offset["items"]) == 1


def test_user_job_state(client: TestClient, user_headers: dict[str, str]) -> None:
    job = create_job(client, user_headers)
    assert job["status"]["is_new"] is True
    detail = client.get(f"{API}/jobs/{job['id']}", headers=user_headers).json()["data"]
    assert detail["status"]["is_new"] is False  # ouverte = vue
    assert detail["description"]
    saved = client.patch(
        f"{API}/jobs/{job['id']}/state", headers=user_headers, json={"is_saved": True}
    ).json()["data"]
    assert saved["status"]["is_saved"] is True
    assert (
        client.get(f"{API}/jobs?status=saved", headers=user_headers).json()["data"]["pagination"][
            "total"
        ]
        == 1
    )
    client.patch(f"{API}/jobs/{job['id']}/state", headers=user_headers, json={"is_ignored": True})
    assert (
        client.get(f"{API}/jobs", headers=user_headers).json()["data"]["pagination"]["total"] == 0
    )
    assert (
        client.get(f"{API}/jobs?status=ignored", headers=user_headers).json()["data"]["items"][0][
            "status"
        ]["state"]
        == "ignored"
    )


def test_job_administration(
    client: TestClient, admin_headers: dict[str, str], user_headers: dict[str, str]
) -> None:
    job = create_job(client, user_headers)
    assert (
        client.put(f"{API}/jobs/{job['id']}", headers=user_headers, json={"title": "X"}).status_code
        == 403
    )
    assert client.get(f"{API}/jobs/{job['id']}/raw", headers=user_headers).status_code == 403
    raw = client.get(f"{API}/jobs/{job['id']}/raw", headers=admin_headers).json()["data"]
    assert raw["raw_data"]["title"].startswith("Développeur")
    assert raw["normalized_data"]["fingerprint"]

    updated = client.put(
        f"{API}/jobs/{job['id']}", headers=admin_headers,
        json={"title": "Développeur Full Stack", "skills": [{"name": "Rust", "requirement": "required"}], "status": "expired"},
    )  # fmt: skip
    assert updated.status_code == 200, updated.text
    assert [skill["name"] for skill in updated.json()["data"]["skills"]] == ["Rust"]
    assert updated.json()["data"]["status"]["is_expired"] is True
    invalid = client.put(f"{API}/jobs/{job['id']}", headers=admin_headers, json={"status": "new"})
    assert invalid.json()["error"]["code"] == "INVALID_JOB_STATUS_TRANSITION"
    assert client.delete(f"{API}/jobs/{job['id']}", headers=admin_headers).status_code == 204
    assert client.get(f"{API}/jobs/{job['id']}", headers=user_headers).status_code == 404


def test_job_maintenance_expires_outdated_jobs(client: TestClient, admin_headers: dict[str, str], db) -> None:  # type: ignore[no-untyped-def]
    from datetime import timedelta

    from app.modules.jobs.models import Job
    from app.shared.utils import utcnow

    job = create_job(client, admin_headers)
    stored = db.get(Job, job["id"])
    stored.last_checked_at = utcnow() - timedelta(days=90)
    db.commit()
    result = client.post(f"{API}/jobs/maintenance/expire", headers=admin_headers).json()["data"]
    assert result["expired"] == 1


def test_match_endpoint_returns_details(client: TestClient, user_headers: dict[str, str]) -> None:
    setup_candidate(client, user_headers)
    job = create_job(client, user_headers)
    response = client.post(f"{API}/jobs/{job['id']}/match", headers=user_headers)
    assert response.status_code == 200
    match = response.json()["data"]
    assert match["score"] >= 80
    assert set(match["matched_skills"]) >= {"Python", "Django", "React"}
    assert match["contract_match"] is True and match["location_match"] is True
    assert match["reasons"]
    assert (
        client.post(
            f"{API}/jobs/00000000-0000-0000-0000-000000000000/match", headers=user_headers
        ).status_code
        == 404
    )


def test_high_match_creates_notification(client: TestClient, user_headers: dict[str, str]) -> None:
    setup_candidate(client, user_headers)
    create_job(client, user_headers)
    notifications = client.get(f"{API}/notifications", headers=user_headers).json()["data"]["items"]
    types = {notification["type"] for notification in notifications}
    assert {"high_match", "new_job"} <= types
    high = next(n for n in notifications if n["type"] == "high_match")
    assert high["data"]["score"] >= 70 and high["data"]["job_title"]


def test_matching_settings_and_recalculation(
    client: TestClient, user_headers: dict[str, str]
) -> None:
    job = create_job(client, user_headers)
    settings = client.get(f"{API}/matching/settings", headers=user_headers).json()["data"]
    assert settings["skills_weight"] == 40 and settings["language_weight"] == 5

    before = client.get(f"{API}/jobs/{job['id']}", headers=user_headers).json()["data"]["matching"]
    setup_candidate(client, user_headers)
    recalculated = client.post(f"{API}/matching/recalculate?background=false", headers=user_headers)
    assert recalculated.status_code == 200
    assert recalculated.json()["data"] == {"status": "done", "jobs_matched": 1}
    after = client.get(f"{API}/jobs/{job['id']}", headers=user_headers).json()["data"]["matching"]
    assert after["score"] > before["score"]

    updated = client.put(
        f"{API}/matching/settings",
        headers=user_headers,
        json={"skills_weight": 0, "contract_weight": 100},
    )
    assert updated.json()["data"]["contract_weight"] == 100
    assert client.post(f"{API}/matching/recalculate", headers=user_headers).status_code == 202
    reset = client.post(f"{API}/matching/settings/reset", headers=user_headers).json()["data"]
    assert reset["skills_weight"] == 40
    assert (
        client.put(
            f"{API}/matching/settings", headers=user_headers, json={"skills_weight": 101}
        ).status_code
        == 422
    )
