from fastapi.testclient import TestClient

from tests.factories import API, pdf_bytes, png_bytes


def test_profile_is_created_empty_then_updated(
    client: TestClient, user_headers: dict[str, str]
) -> None:
    profile = client.get(f"{API}/profile", headers=user_headers).json()["data"]
    assert profile["email"] == "user@example.com"
    assert profile["completion_percent"] < 20

    response = client.put(
        f"{API}/profile",
        headers=user_headers,
        json={
            "first_name": "Jane",
            "last_name": "Doe",
            "country": "fr",
            "experience_level": "mid",
            "languages": [{"code": "FR", "level": "native"}],
            "linkedin_url": "https://www.linkedin.com/in/jane-doe",
            "available_from": "2026-11-01",
            "minimum_salary": 3000,
            "currency": "eur",
            "salary_period": "month",
            "remote": True,
        },
    )
    assert response.status_code == 200, response.text
    data = response.json()["data"]
    assert data["full_name"] == "Jane Doe"
    assert data["country"] == "France"
    assert data["languages"] == [{"code": "fr", "level": "native"}]
    assert data["currency"] == "EUR"
    # Le salaire minimum est la même donnée que dans /preferences.
    preferences = client.get(f"{API}/preferences", headers=user_headers).json()["data"]
    assert preferences["minimum_salary"] == 3000
    assert preferences["salary_period"] == "month"


def test_profile_rejects_unknown_experience_level(
    client: TestClient, user_headers: dict[str, str]
) -> None:
    response = client.put(f"{API}/profile", headers=user_headers, json={"experience_level": "guru"})
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "UNKNOWN_EXPERIENCE_LEVEL"


def test_profile_photo_lifecycle(client: TestClient, user_headers: dict[str, str]) -> None:
    upload = client.post(
        f"{API}/profile/photo",
        headers=user_headers,
        files={"file": ("me.png", png_bytes(), "image/png")},
    )
    assert upload.status_code == 200, upload.text
    assert upload.json()["data"]["photo_url"] == "/api/v1/profile/photo"

    photo = client.get(f"{API}/profile/photo", headers=user_headers)
    assert photo.status_code == 200
    assert photo.headers["content-type"] == "image/png"
    assert photo.headers["x-content-type-options"] == "nosniff"
    assert photo.content == png_bytes()

    # Remplacement : l'ancienne photo est supprimée.
    client.post(
        f"{API}/profile/photo",
        headers=user_headers,
        files={"file": ("me2.png", png_bytes(), "image/png")},
    )
    photos = client.get(f"{API}/documents?document_type=photo", headers=user_headers).json()["data"]
    assert photos["pagination"]["total"] == 1

    assert client.delete(f"{API}/profile/photo", headers=user_headers).status_code == 204
    assert client.get(f"{API}/profile/photo", headers=user_headers).status_code == 404


def test_photo_rejects_non_images(client: TestClient, user_headers: dict[str, str]) -> None:
    response = client.post(
        f"{API}/profile/photo",
        headers=user_headers,
        files={"file": ("cv.pdf", pdf_bytes(), "application/pdf")},
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "INVALID_FILE_EXTENSION"


def test_skills_crud(client: TestClient, user_headers: dict[str, str]) -> None:
    created = client.post(
        f"{API}/skills", headers=user_headers,
        json={"name": "Python", "category": "backend", "level": "advanced", "years_experience": 3, "priority": "high"},
    )  # fmt: skip
    assert created.status_code == 201
    skill = created.json()["data"]
    assert skill["name"] == "Python"  # le catalogue contient déjà Python (seed)
    assert skill["category"] == "backend"

    assert (
        client.post(f"{API}/skills", headers=user_headers, json={"name": "python"}).status_code
        == 409
    )
    updated = client.put(
        f"{API}/skills/{skill['id']}",
        headers=user_headers,
        json={"level": "expert", "enabled": False},
    )
    assert updated.json()["data"]["level"] == "expert"
    assert client.get(f"{API}/skills?enabled_only=true", headers=user_headers).json()["data"] == []
    assert client.get(f"{API}/skills/{skill['id']}", headers=user_headers).status_code == 200
    assert client.delete(f"{API}/skills/{skill['id']}", headers=user_headers).status_code == 204
    assert client.get(f"{API}/skills/{skill['id']}", headers=user_headers).status_code == 404


def test_new_skill_is_added_to_catalog(client: TestClient, user_headers: dict[str, str]) -> None:
    client.post(
        f"{API}/skills", headers=user_headers, json={"name": "Elixir", "category": "backend"}
    )
    catalog = client.get(f"{API}/skills/catalog?search=elix", headers=user_headers).json()["data"][
        "items"
    ]
    assert [item["name"] for item in catalog] == ["Elixir"]
    categories = client.get(f"{API}/skills/categories", headers=user_headers).json()["data"]
    assert "frontend" in {category["code"] for category in categories}


def test_users_cannot_see_each_other_skills(
    client: TestClient, admin_headers: dict[str, str], user_headers: dict[str, str]
) -> None:
    skill = client.post(f"{API}/skills", headers=user_headers, json={"name": "Go"}).json()["data"]
    assert client.get(f"{API}/skills/{skill['id']}", headers=admin_headers).status_code == 404
    assert client.get(f"{API}/skills", headers=admin_headers).json()["data"] == []


def test_experiences_and_technology_preferences(
    client: TestClient, user_headers: dict[str, str]
) -> None:
    experience = client.post(
        f"{API}/experiences", headers=user_headers,
        json={"company_name": "Exemple SAS", "job_title": "Développeur", "start_date": "2022-01-01", "is_current": True},
    )  # fmt: skip
    assert experience.status_code == 201
    assert experience.json()["data"]["duration_years"] > 3

    for name, category in (("React", "frontend"), ("Next.js", "frontend"), ("Django", "backend")):
        response = client.post(
            f"{API}/experience-preferences", headers=user_headers,
            json={"technology": name, "category": category, "priority": "high", "min_years": 1, "is_required": name == "React"},
        )  # fmt: skip
        assert response.status_code == 201, response.text
    grouped = client.get(f"{API}/experience-preferences/grouped", headers=user_headers).json()[
        "data"
    ]
    assert {item["technology"] for item in grouped["frontend"]} == {"React", "Next.js"}
    assert [item["technology"] for item in grouped["backend"]] == ["Django"]
    levels = client.get(f"{API}/experience-levels", headers=user_headers).json()["data"]
    assert [level["code"] for level in levels] == ["internship", "junior", "mid", "senior", "lead"]


def test_job_titles_crud(client: TestClient, user_headers: dict[str, str]) -> None:
    created = client.post(
        f"{API}/job-titles",
        headers=user_headers,
        json={"title": "Python Developer", "priority": "high"},
    )
    assert created.status_code == 201
    job_title_id = created.json()["data"]["id"]
    assert (
        client.post(
            f"{API}/job-titles", headers=user_headers, json={"title": "python developer"}
        ).status_code
        == 409
    )
    updated = client.put(
        f"{API}/job-titles/{job_title_id}",
        headers=user_headers,
        json={"title": "Backend Developer"},
    )
    assert updated.json()["data"]["title"] == "Backend Developer"
    assert (
        client.delete(f"{API}/job-titles/{job_title_id}", headers=user_headers).status_code == 204
    )


def test_contract_types_are_managed_by_admins(
    client: TestClient, admin_headers: dict[str, str], user_headers: dict[str, str]
) -> None:
    codes = [
        item["code"]
        for item in client.get(f"{API}/contract-types", headers=user_headers).json()["data"]
    ]
    assert codes == [
        "cdi",
        "cdd",
        "freelance",
        "stage",
        "alternance",
        "contract",
        "part_time",
        "full_time",
    ]
    payload = {"name": "Portage salarial", "aliases": ["Portage"]}
    assert (
        client.post(f"{API}/contract-types", headers=user_headers, json=payload).status_code == 403
    )
    created = client.post(f"{API}/contract-types", headers=admin_headers, json=payload)
    assert created.status_code == 201
    assert created.json()["data"]["code"] == "portage_salarial"
    contract_id = created.json()["data"]["id"]
    assert (
        client.put(
            f"{API}/contract-types/{contract_id}", headers=admin_headers, json={"is_active": False}
        ).status_code
        == 200
    )
    assert "portage_salarial" not in [
        c["code"] for c in client.get(f"{API}/contract-types", headers=admin_headers).json()["data"]
    ]
    assert (
        client.delete(f"{API}/contract-types/{contract_id}", headers=admin_headers).status_code
        == 204
    )


def test_preferences_update_and_sync(client: TestClient, user_headers: dict[str, str]) -> None:
    response = client.put(
        f"{API}/preferences",
        headers=user_headers,
        json={
            "job_titles": ["Full Stack Developer", "Python Developer"],
            "contract_types": ["cdi", "freelance"],
            "skills": ["React", "Django"],
            "experience_levels": ["mid", "senior"],
            "locations": [{"city": "Paris", "country": "France"}],
            "remote": True,
            "hybrid": False,
            "minimum_salary": 900,
            "currency": "EUR",
            "languages": ["fr", "EN"],
            "matching_threshold": 80,
        },
    )
    assert response.status_code == 200, response.text
    data = response.json()["data"]
    assert data["contract_types"] == ["cdi", "freelance"]
    assert data["skills"] == ["Django", "React"]
    assert data["languages"] == ["en", "fr"]
    assert data["matching_threshold"] == 80

    # Retirer un poste le désactive (ses réglages sont conservés).
    client.put(
        f"{API}/preferences", headers=user_headers, json={"job_titles": ["Python Developer"]}
    )
    titles = client.get(f"{API}/job-titles", headers=user_headers).json()["data"]
    assert {t["title"]: t["enabled"] for t in titles} == {
        "Full Stack Developer": False,
        "Python Developer": True,
    }
    # Champs absents : inchangés.
    assert client.get(f"{API}/preferences", headers=user_headers).json()["data"][
        "contract_types"
    ] == ["cdi", "freelance"]


def test_preferences_reject_unknown_codes(client: TestClient, user_headers: dict[str, str]) -> None:
    response = client.put(
        f"{API}/preferences", headers=user_headers, json={"contract_types": ["cdi", "nope"]}
    )
    assert response.status_code == 422
    assert response.json()["error"] == {
        "code": "UNKNOWN_CONTRACT_TYPE",
        "message": "Unknown contract type(s)",
        "details": {"codes": ["nope"]},
    }


def test_documents_upload_list_download_delete(
    client: TestClient, user_headers: dict[str, str], admin_headers: dict[str, str]
) -> None:
    first = client.post(
        f"{API}/documents", headers=user_headers,
        files={"file": ("CV FR.pdf", pdf_bytes(), "application/pdf")},
        data={"document_type": "cv", "language": "fr", "target_job_title": "Full Stack Developer"},
    )  # fmt: skip
    assert first.status_code == 201, first.text
    first_cv = first.json()["data"]
    assert first_cv["is_primary"] is True  # premier CV = principal
    second = client.post(
        f"{API}/documents", headers=user_headers,
        files={"file": ("cv-en.pdf", pdf_bytes(), "application/octet-stream")},
        data={"document_type": "cv", "language": "en", "is_primary": "true"},
    ).json()["data"]  # fmt: skip
    assert second["is_primary"] is True
    assert (
        client.get(f"{API}/documents/{first_cv['id']}", headers=user_headers).json()["data"][
            "is_primary"
        ]
        is False
    )

    download = client.get(f"{API}/documents/{first_cv['id']}/download", headers=user_headers)
    assert download.status_code == 200
    assert download.content == pdf_bytes()
    assert "attachment" in download.headers["content-disposition"]

    # Fichiers privés : un autre utilisateur ne les voit pas.
    assert (
        client.get(f"{API}/documents/{first_cv['id']}/download", headers=admin_headers).status_code
        == 404
    )
    assert client.get(f"{API}/documents/{first_cv['id']}/download").status_code == 401

    patched = client.patch(
        f"{API}/documents/{first_cv['id']}",
        headers=user_headers,
        json={"title": "CV principal", "is_active": False},
    )
    assert patched.json()["data"]["title"] == "CV principal"
    assert (
        client.delete(f"{API}/documents/{first_cv['id']}", headers=user_headers).status_code == 204
    )
    assert (
        client.get(f"{API}/documents", headers=user_headers).json()["data"]["pagination"]["total"]
        == 1
    )


def test_upload_size_limit(client: TestClient, user_headers: dict[str, str], monkeypatch) -> None:  # type: ignore[no-untyped-def]
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "MAX_UPLOAD_SIZE_MB", 1)
    big = b"%PDF-" + b"0" * (3 * 1024 * 1024)
    response = client.post(
        f"{API}/documents",
        headers=user_headers,
        files={"file": ("big.pdf", big, "application/pdf")},
    )
    assert response.status_code == 413
    assert response.json()["error"]["code"] == "PAYLOAD_TOO_LARGE"
