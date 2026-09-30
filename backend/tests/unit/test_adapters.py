"""Adapters de collecte testés avec un faux serveur HTTP (httpx.MockTransport)."""

import uuid
from collections.abc import Callable

import httpx
import pytest

from app.modules.scraping.adapters.example_api import JsonApiAdapter
from app.modules.scraping.adapters.example_html import HtmlPageAdapter
from app.modules.scraping.adapters.example_rss import RssFeedAdapter
from app.modules.scraping.base import SourceAdapter, SourceContext
from app.modules.scraping.http import PoliteHttpClient, ScrapingBlockedError, ScrapingError
from app.modules.scraping.parser import ParserService
from app.modules.skills.extraction import SkillExtractor
from app.modules.skills.models import Skill
from app.shared.enums import SkillRequirement
from app.shared.utils import is_public_host

RSS = """<?xml version="1.0"?>
<rss version="2.0"><channel><title>Jobs</title>
<item><title>Exemple SAS: Python Developer</title><link>https://example.com/jobs/1</link>
<guid>job-1</guid><description>&lt;p&gt;Python and Django&lt;/p&gt;</description>
<pubDate>Mon, 28 Sep 2026 10:00:00 +0000</pubDate></item>
<item><title>Autre: React Developer</title><link>https://example.com/jobs/2</link><guid>job-2</guid></item>
</channel></rss>"""

ATOM = """<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"><title>Jobs</title>
<entry><title>Backend Engineer</title><link href="https://example.org/j/9"/><id>urn:9</id>
<updated>2026-09-28T10:00:00Z</updated><summary>Go and Kubernetes</summary></entry></feed>"""

API_JSON = {
    "jobs": [
        {
            "id": 123,
            "title": "Full Stack Developer",
            "url": "https://example.com/api-job/123",
            "company_name": "Tech Solutions",
            "candidate_required_location": "Worldwide",
            "job_type": "full_time",
            "salary": "$80k - $100k",
            "publication_date": "2026-09-20T08:00:00",
            "tags": ["python", "react"],
            "description": "<p>Build <b>APIs</b></p>",
        }
    ]
}

HTML = """<html><body>
<article class="job" data-id="a1"><h2>Développeur Python</h2><a href="/careers/a1">Voir</a>
<span class="location">Paris</span></article>
<article class="job" data-id="a2"><h2>Designer UX</h2><a href="/careers/a2">Voir</a></article>
<article class="job"><p>Sans titre</p></article>
</body></html>"""

Handler = Callable[[httpx.Request], httpx.Response]


def build(
    adapter_class: type[SourceAdapter], configuration: dict[str, object], handler: Handler
) -> SourceAdapter:
    http = PoliteHttpClient(
        6000,
        respect_robots_txt=adapter_class.respects_robots_txt,
        transport=httpx.MockTransport(handler),
    )
    context = SourceContext(
        source_id=uuid.uuid4(), name="test", base_url=None, configuration=configuration
    )
    return adapter_class(context, http)


def serve(routes: dict[str, httpx.Response]) -> Handler:
    def handler(request: httpx.Request) -> httpx.Response:
        return routes.get(request.url.path, httpx.Response(404))

    return handler


def test_rss_adapter_parses_items_and_splits_company() -> None:
    adapter = build(
        RssFeedAdapter,
        {"feed_url": "https://example.com/feed.rss", "title_separator": ":"},
        serve(
            {
                "/feed.rss": httpx.Response(
                    200, text=RSS, headers={"content-type": "application/rss+xml"}
                )
            }
        ),
    )
    pages = adapter.fetch()
    jobs = adapter.parse(pages[0])
    assert len(jobs) == 2
    assert jobs[0]["title"] == "Python Developer"
    assert jobs[0]["company"]["name"] == "Exemple SAS"
    assert jobs[0]["description"] == "Python and Django"
    assert jobs[0]["external_id"] == "job-1"
    assert jobs[0]["published_at"].startswith("2026-09-28")


def test_atom_feed_is_supported() -> None:
    adapter = build(
        RssFeedAdapter, {"feed_url": "https://example.org/feed"},
        serve({"/feed": httpx.Response(200, text=ATOM)}),
    )  # fmt: skip
    jobs = adapter.parse(adapter.fetch()[0])
    assert jobs[0]["url"] == "https://example.org/j/9"
    assert jobs[0]["external_id"] == "urn:9"


def test_json_api_adapter_uses_field_map() -> None:
    adapter = build(
        JsonApiAdapter,
        {"url": "https://example.com/api/jobs", "items_path": "jobs", "remote_only": True},
        serve({"/api/jobs": httpx.Response(200, json=API_JSON)}),
    )
    job = adapter.parse(adapter.fetch()[0])[0]
    assert job["external_id"] == 123
    assert job["company"]["name"] == "Tech Solutions"
    assert job["description"] == "Build\nAPIs"
    assert job["location"]["remote"] is True
    assert job["skills"] == ["python", "react"]


def test_html_adapter_extracts_items_and_resolves_links() -> None:
    adapter = build(
        HtmlPageAdapter,
        {
            "list_url": "https://example.com/careers",
            "item_selector": "article.job",
            "fields": {
                "title": "h2",
                "url": "a@href",
                "location": ".location",
                "external_id": "@data-id",
            },
            "company_name": "Exemple SAS",
        },
        serve(
            {
                "/robots.txt": httpx.Response(404),
                "/careers": httpx.Response(200, text=HTML, headers={"content-type": "text/html"}),
            }
        ),
    )
    jobs = adapter.parse(adapter.fetch()[0])
    assert [job["title"] for job in jobs] == ["Développeur Python", "Designer UX"]
    assert jobs[0]["url"] == "https://example.com/careers/a1"
    assert jobs[0]["external_id"] == "a1"
    assert jobs[0]["company"]["name"] == "Exemple SAS"


def test_robots_txt_is_respected() -> None:
    adapter = build(
        HtmlPageAdapter,
        {
            "list_url": "https://example.com/careers",
            "item_selector": "article",
            "fields": {"title": "h2"},
        },
        serve({"/robots.txt": httpx.Response(200, text="User-agent: *\nDisallow: /careers")}),
    )
    with pytest.raises(ScrapingBlockedError, match=r"robots\.txt"):
        adapter.fetch()


@pytest.mark.parametrize("status", [401, 403, 429])
def test_access_refusal_stops_collection(status: int) -> None:
    adapter = build(
        RssFeedAdapter, {"feed_url": "https://example.com/feed"},
        serve({"/robots.txt": httpx.Response(404), "/feed": httpx.Response(status)}),
    )  # fmt: skip
    with pytest.raises(ScrapingBlockedError):
        adapter.fetch()


def test_captcha_page_stops_collection() -> None:
    page = httpx.Response(
        200, text="<html>Please solve the CAPTCHA</html>", headers={"content-type": "text/html"}
    )
    adapter = build(
        HtmlPageAdapter,
        {
            "list_url": "https://example.com/careers",
            "item_selector": "article",
            "fields": {"title": "h2"},
        },
        serve({"/robots.txt": httpx.Response(404), "/careers": page}),
    )
    with pytest.raises(ScrapingBlockedError, match="Anti-bot"):
        adapter.fetch()


def test_invalid_json_is_a_scraping_error() -> None:
    adapter = build(
        JsonApiAdapter, {"url": "https://example.com/api"},
        serve({"/api": httpx.Response(200, text="not json")}),
    )  # fmt: skip
    with pytest.raises(ScrapingError):
        adapter.parse(adapter.fetch()[0])


def test_private_addresses_are_blocked() -> None:
    assert not is_public_host("127.0.0.1")
    assert not is_public_host("localhost")
    client = PoliteHttpClient(
        600, respect_robots_txt=False, transport=httpx.MockTransport(lambda r: httpx.Response(200))
    )
    client.allow_private_urls = False
    with pytest.raises(ScrapingBlockedError):
        client.get_text("http://127.0.0.1/admin")


def test_parser_service_validates_items() -> None:
    adapter = build(
        RssFeedAdapter, {"feed_url": "https://example.com/feed"},
        serve({"/robots.txt": httpx.Response(404), "/feed": httpx.Response(200, text=RSS)}),
    )  # fmt: skip
    result = ParserService().parse(adapter, adapter.fetch(), max_jobs=1)
    assert len(result.jobs) == 1
    assert "Limit of 1 jobs" in result.errors[0]


def test_skill_extractor_detects_required_and_preferred() -> None:
    skills = [
        Skill(name="Python", normalized_name="python", aliases=[]),
        Skill(name="React", normalized_name="react", aliases=["reactjs"]),
        Skill(name="Docker", normalized_name="docker", aliases=[]),
        Skill(name="C++", normalized_name="c++", aliases=[]),
        Skill(name="Go", normalized_name="go", aliases=["golang"]),
    ]
    extractor = SkillExtractor(skills)
    found = dict(
        extractor.extract(
            "Développeur Python",
            "Stack : Python et ReactJS. Docker serait un plus. Let's go to production.",
        )
    )
    assert found == {
        "Python": SkillRequirement.REQUIRED,
        "React": SkillRequirement.REQUIRED,
        "Docker": SkillRequirement.PREFERRED,
    }
    assert dict(extractor.extract("C++ engineer", "Golang et C++")) == {
        "C++": SkillRequirement.REQUIRED,
        "Go": SkillRequirement.REQUIRED,
    }
