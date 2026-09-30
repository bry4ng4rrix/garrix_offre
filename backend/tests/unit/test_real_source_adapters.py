"""Adapters configurés comme les sources réelles du seed (réponses HTTP simulées)."""

import json
import uuid

import httpx
import pytest

from app.core.config import get_settings
from app.modules.scraping.adapters.example_api import JsonApiAdapter
from app.modules.scraping.adapters.france_travail import FranceTravailAdapter
from app.modules.scraping.base import SourceContext
from app.modules.scraping.email_alerts import JobAlertEmailParser
from app.modules.scraping.http import PoliteHttpClient, ScrapingError
from app.modules.scraping.schemas import JobPayload
from app.modules.sources.models import Source
from scripts.seed import ALERT_EMAIL_SOURCES, API_AND_RSS_SOURCES


def seed_config(name: str) -> dict:
    return next(source for source in API_AND_RSS_SOURCES if source["name"] == name)["configuration"]


def adapter_for(adapter_class, configuration: dict, handler) -> object:  # type: ignore[no-untyped-def]
    http = PoliteHttpClient(6000, respect_robots_txt=False, transport=httpx.MockTransport(handler))
    return adapter_class(SourceContext(uuid.uuid4(), "test", None, configuration), http)


def test_remote_ok_configuration() -> None:
    body = [
        {"last_updated": 1, "legal": "API Terms of Service: please link back"},
        {
            "id": "1098", "position": "Senior Python Engineer", "company": "Acme",
            "location": "Worldwide", "tags": ["python", "django"], "description": "<p>Build APIs</p>",
            "url": "https://remoteOK.com/remote-jobs/1098", "apply_url": "https://acme.example/apply",
            "date": "2026-09-28T10:00:00+00:00", "salary_min": 90000, "salary_max": 0,
        },
    ]  # fmt: skip
    adapter = adapter_for(
        JsonApiAdapter, seed_config("Remote OK"), lambda r: httpx.Response(200, json=body)
    )
    jobs = adapter.parse(adapter.fetch()[0])  # type: ignore[attr-defined]
    assert len(jobs) == 1  # la mention légale est ignorée
    payload = JobPayload.model_validate(jobs[0])
    assert payload.title == "Senior Python Engineer"
    assert payload.salary and (payload.salary.min, payload.salary.max, payload.salary.currency) == (
        90000,
        None,
        "USD",
    )
    assert payload.location and payload.location.remote is True
    assert payload.application and payload.application.url == "https://acme.example/apply"


def test_freelancer_configuration() -> None:
    body = {
        "status": "success",
        "result": {
            "projects": [
                {
                    "id": 40741658, "title": "Build a FastAPI backend", "seo_url": "python/Build-FastAPI-backend",
                    "description": "Need an API", "time_submitted": 1790742234, "type": "fixed",
                    "currency": {"code": "USD"}, "budget": {"minimum": 250.0, "maximum": 750.0},
                    "jobs": [{"name": "Python"}, {"name": "FastAPI"}],
                }
            ]
        },
    }  # fmt: skip
    adapter = adapter_for(
        JsonApiAdapter, seed_config("Freelancer.com"), lambda r: httpx.Response(200, json=body)
    )
    payload = JobPayload.model_validate(adapter.parse(adapter.fetch()[0])[0])  # type: ignore[attr-defined]
    assert payload.url == "https://www.freelancer.com/projects/python/Build-FastAPI-backend"
    assert [skill.name for skill in payload.skills] == ["Python", "FastAPI"]
    assert payload.contract and payload.contract.type == "Freelance"
    assert payload.description and "Budget maximum : 750.0" in payload.description
    assert payload.published_at and payload.published_at.year == 2026


def test_france_travail_requires_credentials(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(get_settings(), "FRANCE_TRAVAIL_CLIENT_ID", None)
    adapter = adapter_for(
        FranceTravailAdapter, {"keywords": "python"}, lambda r: httpx.Response(500)
    )
    with pytest.raises(ScrapingError, match="FRANCE_TRAVAIL_CLIENT_ID"):
        adapter.fetch()  # type: ignore[attr-defined]


def test_france_travail_oauth_and_mapping(monkeypatch: pytest.MonkeyPatch) -> None:
    from pydantic import SecretStr

    monkeypatch.setattr(get_settings(), "FRANCE_TRAVAIL_CLIENT_ID", "client")
    monkeypatch.setattr(get_settings(), "FRANCE_TRAVAIL_CLIENT_SECRET", SecretStr("secret"))
    calls: list[httpx.Request] = []
    offer = {
        "id": "123ABC", "intitule": "Développeur Python H/F", "description": "Python, Django, PostgreSQL",
        "dateCreation": "2026-09-27T08:00:00.000Z", "lieuTravail": {"libelle": "75 - Paris 1er Arrondissement"},
        "entreprise": {"nom": "Exemple SAS"}, "typeContrat": "CDI", "dureeTravailLibelleConverti": "Temps plein",
        "salaire": {"libelle": "Annuel de 40000.00 Euros à 48000.00 Euros sur 12 mois"},
        "experienceLibelle": "3 ans", "langues": [{"libelle": "Anglais", "exigence": "S"}],
        "contact": {"nom": "Service RH", "courriel": "rh@exemple.example", "urlPostulation": "https://exemple.example/postuler"},
    }  # fmt: skip

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        if request.url.host == "entreprise.francetravail.fr":
            return httpx.Response(200, json={"access_token": "tok", "expires_in": 1499})
        assert request.headers["Authorization"] == "Bearer tok"
        return httpx.Response(200, json={"resultats": [offer]})

    adapter = adapter_for(
        FranceTravailAdapter, {"keywords": "python", "departement": "75"}, handler
    )
    pages = adapter.fetch()  # type: ignore[attr-defined]
    token_request, search_request = calls
    assert b"grant_type=client_credentials" in token_request.content
    assert search_request.url.params["motsCles"] == "python"
    assert search_request.url.params["range"] == "0-149"

    payload = JobPayload.model_validate(adapter.parse(pages[0])[0])  # type: ignore[attr-defined]
    assert payload.url == "https://candidat.francetravail.fr/offres/recherche/detail/123ABC"
    assert payload.location and payload.location.raw == "75 - Paris, France"
    assert payload.contract and payload.contract.type == "CDI"
    assert payload.recruiter and payload.recruiter.contact_source == "api"
    assert payload.languages == ["Anglais"]


def alert_sources() -> list[Source]:
    return [Source(**source) for source in ALERT_EMAIL_SOURCES]


def test_alert_email_extracts_job_links_only() -> None:
    html = """
    <p>Nouvelles offres pour « Développeur Python »</p>
    <a href="https://www.linkedin.com/comm/jobs/view/4012345678/?trackingId=abc&alertAction=view">Développeur Python Senior</a>
    <a href="https://www.linkedin.com/comm/jobs/view/4012345679/">Backend Engineer (Django)</a>
    <a href="https://www.linkedin.com/comm/jobs/view/4012345679/?refId=zz">Backend Engineer (Django)</a>
    <a href="https://www.linkedin.com/comm/jobs/search?keywords=python">Voir toutes les offres</a>
    <a href="https://www.linkedin.com/comm/psettings/email-unsubscribe">Se désabonner</a>
    <a href="https://evil.example/jobs/1">Offre externe suspecte</a>
    """
    extraction = JobAlertEmailParser(alert_sources()).extract(
        "jobalerts-noreply@linkedin.com", html, None
    )
    assert extraction.source is not None and extraction.source.name == "LinkedIn"
    assert [job["title"] for job in extraction.jobs] == [
        "Développeur Python Senior",
        "Backend Engineer (Django)",
    ]
    assert (
        extraction.jobs[0]["url"]
        == "https://www.linkedin.com/comm/jobs/view/4012345678?alertAction=view"
    )


def test_alert_email_plain_text_and_subdomains() -> None:
    text = "Développeur Full Stack H/F\nhttps://fr.indeed.com/rc/clk?jk=abc123\n\nSe désabonner\nhttps://fr.indeed.com/unsubscribe"
    extraction = JobAlertEmailParser(alert_sources()).extract("alert@indeed.com", None, text)
    assert extraction.source is not None and extraction.source.name == "Indeed"
    assert [job["title"] for job in extraction.jobs] == ["Développeur Full Stack H/F"]


def test_unknown_sender_keeps_same_domain_links() -> None:
    html = '<a href="https://jobs.unknown.example/job/42">Data Engineer</a><a href="https://other.example/job/1">Autre</a>'
    extraction = JobAlertEmailParser(alert_sources()).extract("news@unknown.example", html, None)
    assert extraction.source is None
    assert [job["title"] for job in extraction.jobs] == ["Data Engineer"]
    assert json.dumps(extraction.jobs)  # sérialisable (envoyé au pipeline)


def test_secrets_come_from_source_prefixed_env_vars(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.modules.scraping.adapters.common import resolve_secret

    monkeypatch.setenv("SOURCE_TEST_KEY", "s3cr3t")
    assert resolve_secret("SOURCE_TEST_KEY") == "s3cr3t"
    assert resolve_secret("Token {SOURCE_TEST_KEY}") == "Token s3cr3t"
    monkeypatch.delenv("SOURCE_TEST_KEY")
    with pytest.raises(ScrapingError, match="SOURCE_TEST_KEY"):
        resolve_secret("SOURCE_TEST_KEY")


def test_source_config_cannot_reference_other_secrets() -> None:
    from pydantic import ValidationError

    from app.modules.scraping.adapters.example_api import JsonApiConfig

    with pytest.raises(ValidationError):
        JsonApiConfig(
            url="https://api.example.com", secret_headers={"Authorization": "{JWT_SECRET_KEY}"}
        )


def test_jobdatalake_configuration_uses_header_key(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SOURCE_JOBDATALAKE_API_KEY", "dl-key")
    seen: list[httpx.Request] = []
    body = {
        "found": 1, "page": 1, "per_page": 50,
        "jobs": [{
            "title": "Senior Backend Engineer", "company_name": "Stripe", "posted_at": 1775520869,
            "locations": ["San Francisco, CA", "Remote"], "remote_type": "fully_remote", "seniority": ["Senior"],
            "salary_min_usd": 180, "salary_max_usd": 250, "required_skills": ["Python", "AWS"],
            "employment_type": "full_time", "url": "https://stripe.com/jobs/1", "job_handle": "stripe-sbe-1",
        }],
    }  # fmt: skip

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json=body)

    adapter = adapter_for(JsonApiAdapter, seed_config("JobDataLake"), handler)
    page = adapter.fetch()[0]  # type: ignore[attr-defined]
    assert seen[0].headers["X-API-Key"] == "dl-key"
    assert "dl-key" not in page.url
    payload = JobPayload.model_validate(adapter.parse(page)[0])  # type: ignore[attr-defined]
    assert payload.salary and (payload.salary.min, payload.salary.max) == (180000, 250000)
    assert payload.location and payload.location.remote is True
    assert payload.experience_level == "Senior"
    assert payload.external_id == "stripe-sbe-1"


def test_adzuna_configuration_uses_query_keys(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SOURCE_ADZUNA_APP_ID", "id-1")
    monkeypatch.setenv("SOURCE_ADZUNA_APP_KEY", "key-1")
    seen: list[httpx.Request] = []
    body = {"results": [{
        "id": "42", "title": "Développeur Python", "description": "Python Django", "redirect_url": "https://www.adzuna.fr/details/42",
        "company": {"display_name": "Exemple SAS"}, "location": {"display_name": "Paris, Ile-de-France"},
        "contract_type": "permanent", "salary_min": 40000, "salary_max": 50000, "created": "2026-09-28T10:00:00Z",
    }]}  # fmt: skip

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json=body)

    adapter = adapter_for(JsonApiAdapter, seed_config("Adzuna"), handler)
    page = adapter.fetch()[0]  # type: ignore[attr-defined]
    assert seen[0].url.params["app_key"] == "key-1"
    assert "key-1" not in page.url
    payload = JobPayload.model_validate(adapter.parse(page)[0])  # type: ignore[attr-defined]
    assert payload.company and payload.company.name == "Exemple SAS"
    assert payload.salary and payload.salary.currency == "EUR"


def test_jobgether_configuration() -> None:
    body = {"jobs": [{
        "id": "6ab5", "title": "Backend Developer", "company": "HOKA", "url": "https://jobgether.com/offer/6ab5-backend",
        "location": "Spain", "remote": "Full Remote", "contractType": "Full time",
        "experience": "Senior (5-10 years)", "postedAt": "2026-09-24T18:31:18.358Z",
    }], "pagination": {"page": 1, "limit": 25, "hasMore": False}}  # fmt: skip
    adapter = adapter_for(
        JsonApiAdapter, seed_config("Jobgether"), lambda r: httpx.Response(200, json=body)
    )
    pages = adapter.fetch()  # type: ignore[attr-defined]
    payload = JobPayload.model_validate(adapter.parse(pages[0])[0])  # type: ignore[attr-defined]
    assert payload.location and payload.location.remote is True
    assert payload.contract and payload.contract.type == "Full time"
    assert payload.experience_level == "Senior (5-10 years)"
