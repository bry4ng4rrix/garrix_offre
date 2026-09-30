"""Adapter "rss_feed" : flux RSS 2.0 ou Atom publics.

Exemple de configuration :

    {
      "feed_url": "https://example.com/jobs.rss",
      "extra_feed_urls": ["https://example.com/other-category.rss"],
      "title_separator": ":",     # "Entreprise: Titre du poste" -> sépare les deux
      "remote_only": false,
      "default_location": "France"
    }

Le XML est lu avec defusedxml (protection contre les attaques XML).
"""

from email.utils import parsedate_to_datetime
from typing import Any
from xml.etree.ElementTree import Element

from defusedxml import ElementTree
from pydantic import BaseModel, Field, HttpUrl

from app.modules.scraping.adapters.common import html_to_text
from app.modules.scraping.base import FetchedPage, SourceAdapter
from app.modules.scraping.http import ScrapingError
from app.modules.scraping.registry import register_adapter
from app.shared.enums import SourceType

ATOM_NS = "{http://www.w3.org/2005/Atom}"
CONTENT_NS = "{http://purl.org/rss/1.0/modules/content/}"


class RssFeedConfig(BaseModel):
    feed_url: HttpUrl
    extra_feed_urls: list[HttpUrl] = Field(
        default_factory=list, max_length=10, description="Autres flux du même site (catégories)"
    )
    title_separator: str | None = Field(
        default=None, max_length=5, description='Ex: ":" si les titres sont "Entreprise: Poste"'
    )
    company_name: str | None = Field(
        default=None, description="Si le flux concerne une seule entreprise"
    )
    default_location: str | None = None
    default_contract: str | None = Field(
        default=None, description='Ex : "Freelance" pour un flux de missions'
    )
    remote_only: bool = False
    max_items: int = Field(default=100, ge=1, le=500)


@register_adapter
class RssFeedAdapter(SourceAdapter):
    key = "rss_feed"
    description = "Flux RSS 2.0 / Atom public"
    source_types = frozenset({SourceType.RSS})
    config_model = RssFeedConfig
    config: RssFeedConfig

    def fetch(self) -> list[FetchedPage]:
        pages = []
        for feed_url in [self.config.feed_url, *self.config.extra_feed_urls]:
            response = self.http.get_text(str(feed_url))
            pages.append(
                FetchedPage(
                    url=str(response.url), content=response.text, content_type="application/xml"
                )
            )
        return pages

    def parse(self, page: FetchedPage) -> list[dict[str, Any]]:
        try:
            root = ElementTree.fromstring(page.content.encode("utf-8"))
        except ElementTree.ParseError as exc:
            raise ScrapingError("Invalid RSS/Atom XML") from exc
        entries = root.findall("./channel/item") or root.findall(f"{ATOM_NS}entry")
        return [self._entry_to_payload(entry) for entry in entries[: self.config.max_items]]

    def _entry_to_payload(self, entry: Element) -> dict[str, Any]:
        is_atom = entry.tag.startswith(ATOM_NS)
        title = _text(entry, f"{ATOM_NS}title" if is_atom else "title") or ""
        company = self.config.company_name
        if self.config.title_separator and self.config.title_separator in title:
            company_part, title = title.split(self.config.title_separator, 1)
            company = company or company_part.strip()

        if is_atom:
            link_element = entry.find(f"{ATOM_NS}link")
            link = link_element.get("href") if link_element is not None else None
            guid = _text(entry, f"{ATOM_NS}id")
            body = _text(entry, f"{ATOM_NS}content") or _text(entry, f"{ATOM_NS}summary")
            published = _text(entry, f"{ATOM_NS}published") or _text(entry, f"{ATOM_NS}updated")
            categories = [c.get("term", "") for c in entry.findall(f"{ATOM_NS}category")]
        else:
            link = _text(entry, "link")
            guid = _text(entry, "guid")
            body = _text(entry, f"{CONTENT_NS}encoded") or _text(entry, "description")
            published = _text(entry, "pubDate")
            categories = [c.text or "" for c in entry.findall("category")]

        location: dict[str, Any] = {"raw": _text(entry, "region") or self.config.default_location}
        if self.config.remote_only:
            location["remote"] = True
        return {
            "external_id": guid or link,
            "title": title.strip(),
            "description": html_to_text(body),
            "url": link,
            "company": {"name": company},
            "location": location,
            "contract": self.config.default_contract,
            "published_at": _parse_date(published),
            "raw_data": {"title": title, "link": link, "guid": guid, "categories": categories},
        }


def _text(element: Element, tag: str) -> str | None:
    child = element.find(tag)
    if child is None or child.text is None:
        return None
    return child.text.strip() or None


def _parse_date(value: str | None) -> str | None:
    """Les dates RSS sont au format RFC 822 ; Atom utilise ISO 8601 (déjà compris par Pydantic)."""
    if not value:
        return None
    try:
        return parsedate_to_datetime(value).isoformat()
    except (TypeError, ValueError):
        return value
