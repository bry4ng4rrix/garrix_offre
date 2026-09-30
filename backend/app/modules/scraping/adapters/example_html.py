"""Adapter "html_page" : page HTML publique listant des offres.

À n'utiliser QUE pour un site dont les conditions d'utilisation autorisent la collecte
automatique (la source doit avoir `terms_reviewed=true`). robots.txt est toujours respecté,
et la collecte s'arrête dès qu'une protection (CAPTCHA, anti-bot, 403/429) apparaît.

Exemple de configuration :

    {
      "list_url": "https://example.com/careers",
      "item_selector": "article.job",
      "fields": {
        "title": "h2",
        "url": "a@href",
        "location": ".location",
        "contract": ".contract",
        "external_id": "@data-id"
      },
      "company_name": "Exemple SAS",
      "detail_description_selector": ".job-description"
    }

Syntaxe d'un champ : "sélecteur CSS" (texte), "sélecteur@attribut", ou "@attribut"
(attribut de l'élément de la liste lui-même).
"""

from typing import Any
from urllib.parse import urljoin

from bs4 import BeautifulSoup, Tag
from pydantic import BaseModel, Field, HttpUrl

from app.modules.scraping.base import FetchedPage, SourceAdapter
from app.modules.scraping.registry import register_adapter
from app.shared.enums import SourceType


class HtmlPageConfig(BaseModel):
    list_url: HttpUrl
    item_selector: str = Field(min_length=1, max_length=200)
    fields: dict[str, str] = Field(description="Champ JobPayload -> sélecteur CSS")
    company_name: str | None = None
    detail_description_selector: str | None = Field(
        default=None,
        description="Si renseigné, la page de chaque offre est lue pour la description",
    )
    next_page_selector: str | None = Field(default=None, description="Lien vers la page suivante")
    max_pages: int = Field(default=1, ge=1, le=10)
    max_items: int = Field(default=50, ge=1, le=200)


@register_adapter
class HtmlPageAdapter(SourceAdapter):
    key = "html_page"
    description = "Page HTML publique autorisée (sélecteurs CSS configurables)"
    source_types = frozenset({SourceType.HTML})
    config_model = HtmlPageConfig
    config: HtmlPageConfig

    def fetch(self) -> list[FetchedPage]:
        pages: list[FetchedPage] = []
        url: str | None = str(self.config.list_url)
        while url and len(pages) < self.config.max_pages:
            response = self.http.get_text(url)
            pages.append(
                FetchedPage(url=str(response.url), content=response.text, content_type="text/html")
            )
            url = self._next_page_url(response.text, str(response.url))
        return pages

    def parse(self, page: FetchedPage) -> list[dict[str, Any]]:
        soup = BeautifulSoup(page.content, "html.parser")
        jobs = []
        for item in soup.select(self.config.item_selector)[: self.config.max_items]:
            values = {
                field: self._extract(item, selector, page.url)
                for field, selector in self.config.fields.items()
            }
            if not values.get("title"):
                continue
            company = values.pop("company", None) or self.config.company_name
            jobs.append(
                {
                    **values,
                    "company": {"name": company},
                    "raw_data": {"html": str(item)[:5000], "page_url": page.url},
                }
            )
        return jobs

    def enrich(self, job: dict[str, Any]) -> dict[str, Any]:
        """Lit la page de détail de l'offre pour récupérer la description complète."""
        selector = self.config.detail_description_selector
        if not selector or not job.get("url") or job.get("description"):
            return job
        response = self.http.get_text(job["url"])
        element = BeautifulSoup(response.text, "html.parser").select_one(selector)
        if element is not None:
            job["description"] = element.get_text("\n", strip=True)
        return job

    def _next_page_url(self, html: str, current_url: str) -> str | None:
        if not self.config.next_page_selector:
            return None
        link = BeautifulSoup(html, "html.parser").select_one(self.config.next_page_selector)
        href = link.get("href") if link is not None else None
        return urljoin(current_url, href) if isinstance(href, str) else None

    @staticmethod
    def _extract(item: Tag, selector: str, page_url: str) -> str | None:
        css, _, attribute = selector.partition("@")
        element = item.select_one(css) if css else item
        if element is None:
            return None
        if attribute:
            value = element.get(attribute)
            if not isinstance(value, str):
                return None
            return urljoin(page_url, value) if attribute in {"href", "src"} else value.strip()
        return element.get_text(" ", strip=True) or None
