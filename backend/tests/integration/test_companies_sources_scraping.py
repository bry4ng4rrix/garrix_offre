import httpx
import pytest
from fastapi.testclient import TestClient

from app.modules.scraping.scraper import ScraperService
from tests.factories import API, create_job

RSS = """<?xml version="1.0"?><rss version="2.0"><channel><title>Jobs</title>
<item><title>Exemple SAS: Développeur Python Django</title><link>https://jobs.example.com/1</link><guid>r1</guid>
<description>Nous recherchons un développeur Python et Django pour notre équipe à Paris. Vous travaillerez
avec les équipes produit sur une plateforme en production. CDI, 3 ans d'expérience.</description></item>
<item><title>Autre Corp: React Developer</title><link>https://jobs.example.com/2</link><guid>r2</guid></item>
</channel></rss>"""


@pytest.fixture
def fake_web(monkeypatch: pytest.MonkeyPatch) -> list[str]:
    """Remplace Internet par un faux serveur pour toutes les collectes du test."""
    requested: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requested.append(request.url.path)
        if request.url.path == "/feed.rss":
            return httpx.Response(200, text=RSS, headers={"content-type": "application/rss+xml"})
        if request.url.path == "/blocked.rss":
            return httpx.Response(403)
        return httpx.Response(404)

    original_init = ScraperService.__init__

    def init_with_fake_transport(
        self: ScraperService, transport: httpx.BaseTransport | None = None
    ) -> None:
        original_init(self, httpx.MockTransport(handler))

    monkeypatch.setattr(ScraperService, "__init__", init_with_fake_transport)
    return requested


def create_rss_source(client: TestClient, headers: dict[str, str], feed: str = "feed.rss") -> dict:
    response = client.post(
        f"{API}/sources",
        headers=headers,
        json={
            "name": f"RSS {feed}",
            "type": "rss",
            "adapter": "rss_feed",
            "base_url": "https://jobs.example.com",
            "scraping_enabled": True,
            "rate_limit": 600,
            "configuration": {
                "feed_url": f"https://jobs.example.com/{feed}",
                "title_separator": ":",
                "default_location": "Paris, France",
            },
        },
    )
    assert response.status_code == 201, response.text
    return response.json()["data"]


def test_companies_crud(
    client: TestClient, admin_headers: dict[str, str], user_headers: dict[str, str]
) -> None:
    payload = {
        "name": "Tech Solutions",
        "website": "https://example.com",
        "city": "Paris",
        "country": "fr",
    }
    assert client.post(f"{API}/companies", headers=user_headers, json=payload).status_code == 403
    created = client.post(f"{API}/companies", headers=admin_headers, json=payload)
    assert created.status_code == 201
    company = created.json()["data"]
    assert company["country"] == "France"
    assert company["data_source"] == "manual"
    assert (
        client.post(
            f"{API}/companies", headers=admin_headers, json={"name": "TECH SOLUTIONS SAS"}
        ).status_code
        == 409
    )
    listed = client.get(f"{API}/companies?search=tech", headers=user_headers).json()["data"]
    assert listed["pagination"]["total"] == 1
    updated = client.put(
        f"{API}/companies/{company['id']}", headers=admin_headers, json={"industry": "Logiciel"}
    )
    assert updated.json()["data"]["industry"] == "Logiciel"
    assert (
        client.delete(f"{API}/companies/{company['id']}", headers=admin_headers).status_code == 204
    )


def test_collected_company_keeps_provenance(
    client: TestClient, admin_headers: dict[str, str]
) -> None:
    job = create_job(
        client,
        admin_headers,
        company={"name": "Provenance SA", "email": "contact@provenance.example"},
    )
    company = client.get(f"{API}/companies/{job['company']['id']}", headers=admin_headers).json()[
        "data"
    ]
    assert company["email"] == "contact@provenance.example"
    assert company["field_sources"]["email"] == "https://example.com/jobs/1"
    assert company["data_source"] == "manual"


def test_recruiters_require_provenance(client: TestClient, admin_headers: dict[str, str]) -> None:
    missing = client.post(
        f"{API}/recruiters",
        headers=admin_headers,
        json={"name": "Alex", "email": "alex@example.com"},
    )
    assert missing.status_code == 422
    created = client.post(
        f"{API}/recruiters", headers=admin_headers,
        json={"name": "Alex", "email": "alex@example.com", "contact_source": "job_listing", "source_url": "https://example.com/j/1"},
    )  # fmt: skip
    assert created.status_code == 201
    recruiter_id = created.json()["data"]["id"]
    # Mise à jour : la règle s'applique à l'état final (provenance déjà connue -> OK).
    assert (
        client.put(
            f"{API}/recruiters/{recruiter_id}",
            headers=admin_headers,
            json={"phone": "+33 1 23 45 67 89"},
        ).status_code
        == 200
    )
    cleared = client.put(
        f"{API}/recruiters/{recruiter_id}", headers=admin_headers, json={"contact_source": None}
    )
    assert cleared.status_code == 422
    assert cleared.json()["error"]["code"] == "CONTACT_PROVENANCE_REQUIRED"


def test_recruiter_from_job_is_reused(client: TestClient, admin_headers: dict[str, str]) -> None:
    recruiter = {"name": "Alex Martin", "email": "Jobs@Example.com"}
    first = create_job(client, admin_headers, recruiter=recruiter)
    second = create_job(
        client,
        admin_headers,
        external_id="job-2",
        url="https://example.com/jobs/2",
        title="Autre poste Python",
        recruiter=recruiter,
    )
    assert first["recruiter"]["id"] == second["recruiter"]["id"]
    assert first["recruiter"]["email"] == "jobs@example.com"
    assert first["recruiter"]["contact_source"] == "job_listing"


def test_source_configuration_is_validated_by_adapter(
    client: TestClient, admin_headers: dict[str, str]
) -> None:
    bad = client.post(
        f"{API}/sources", headers=admin_headers,
        json={"name": "Bad", "type": "rss", "adapter": "rss_feed", "configuration": {"feed_url": "not a url"}},
    )  # fmt: skip
    assert bad.status_code == 422
    assert bad.json()["error"]["code"] == "INVALID_SOURCE_CONFIGURATION"
    mismatch = client.post(
        f"{API}/sources", headers=admin_headers,
        json={"name": "Mismatch", "type": "api", "adapter": "rss_feed", "configuration": {"feed_url": "https://x.example"}},
    )  # fmt: skip
    assert mismatch.json()["error"]["code"] == "ADAPTER_TYPE_MISMATCH"
    unknown = client.post(
        f"{API}/sources",
        headers=admin_headers,
        json={"name": "U", "type": "api", "adapter": "nope"},
    )
    assert unknown.json()["error"]["code"] == "UNKNOWN_ADAPTER"


def test_adapters_are_listed_with_schema(client: TestClient, user_headers: dict[str, str]) -> None:
    adapters = client.get(f"{API}/scraping/adapters", headers=user_headers).json()["data"]
    assert {adapter["key"] for adapter in adapters} == {
        "json_api",
        "rss_feed",
        "html_page",
        "france_travail_api",
    }
    assert all("properties" in adapter["configuration_schema"] for adapter in adapters)


def test_html_source_requires_terms_review(
    client: TestClient, admin_headers: dict[str, str]
) -> None:
    sources = client.get(f"{API}/sources?type=html", headers=admin_headers).json()["data"]["items"]
    html_source = sources[0]
    client.put(f"{API}/sources/{html_source['id']}", headers=admin_headers, json={"enabled": True})
    response = client.post(f"{API}/sources/{html_source['id']}/run", headers=admin_headers)
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "SOURCE_TERMS_NOT_REVIEWED"


def test_source_test_is_a_dry_run(
    client: TestClient, admin_headers: dict[str, str], fake_web: list[str]
) -> None:
    source = create_rss_source(client, admin_headers)
    response = client.post(f"{API}/sources/{source['id']}/test", headers=admin_headers)
    assert response.status_code == 200, response.text
    data = response.json()["data"]
    assert data["jobs_parsed"] == 2
    assert data["preview"][0]["company_name"] == "Exemple SAS"
    assert data["preview"][0]["contract_type"] == "cdi"
    assert "/robots.txt" in fake_web  # robots.txt consulté avant le flux
    assert (
        client.get(f"{API}/jobs?status=all", headers=admin_headers).json()["data"]["pagination"][
            "total"
        ]
        == 0
    )


def test_full_scraping_run(
    client: TestClient, admin_headers: dict[str, str], fake_web: list[str]
) -> None:
    source = create_rss_source(client, admin_headers)
    response = client.post(f"{API}/sources/{source['id']}/run", headers=admin_headers)
    assert response.status_code == 202, response.text
    run_id = response.json()["data"]["run_id"]

    run = client.get(f"{API}/scraping/runs/{run_id}", headers=admin_headers).json()["data"]
    assert run["status"] == "success"
    assert (run["jobs_found"], run["jobs_created"]) == (2, 2)
    jobs = client.get(f"{API}/jobs?status=all&source={source['id']}", headers=admin_headers).json()[
        "data"
    ]
    assert jobs["pagination"]["total"] == 2
    python_job = next(job for job in jobs["items"] if "Python" in job["title"])
    assert python_job["status"]["state"] == "active"
    assert {skill["name"] for skill in python_job["skills"]} >= {"Python", "Django"}
    react_job = next(job for job in jobs["items"] if "React" in job["title"])
    assert react_job["status"]["state"] == "new"  # incomplète : pas de description
    assert "missing_description" in react_job["quality_issues"]

    # Deuxième collecte : aucune nouvelle offre (déduplication).
    second = client.post(f"{API}/sources/{source['id']}/run", headers=admin_headers).json()["data"]
    run2 = client.get(f"{API}/scraping/runs/{second['run_id']}", headers=admin_headers).json()[
        "data"
    ]
    assert (run2["jobs_created"], run2["jobs_duplicates"]) == (0, 2)
    refreshed = client.get(f"{API}/sources/{source['id']}", headers=admin_headers).json()["data"]
    assert refreshed["last_success_at"] is not None and refreshed["last_error"] is None


def test_blocked_source_fails_and_notifies_admins(
    client: TestClient, admin_headers: dict[str, str], fake_web: list[str]
) -> None:
    source = create_rss_source(client, admin_headers, feed="blocked.rss")
    run_id = client.post(f"{API}/sources/{source['id']}/run", headers=admin_headers).json()["data"][
        "run_id"
    ]
    run = client.get(f"{API}/scraping/runs/{run_id}", headers=admin_headers).json()["data"]
    assert run["status"] == "failed"
    assert "HTTP 403" in run["error_message"]
    notifications = client.get(
        f"{API}/notifications?type=scraping_error", headers=admin_headers
    ).json()["data"]
    assert notifications["pagination"]["total"] == 1
    assert client.get(f"{API}/sources/{source['id']}", headers=admin_headers).json()["data"][
        "last_error"
    ]


def test_cannot_cancel_finished_run(
    client: TestClient, admin_headers: dict[str, str], fake_web: list[str]
) -> None:
    source = create_rss_source(client, admin_headers)
    run_id = client.post(f"{API}/sources/{source['id']}/run", headers=admin_headers).json()["data"][
        "run_id"
    ]
    response = client.post(f"{API}/scraping/runs/{run_id}/cancel", headers=admin_headers)
    assert response.json()["error"]["code"] == "SCRAPING_RUN_FINISHED"
