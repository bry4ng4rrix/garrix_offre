"""Adapter "json_api" : API JSON officielle et publique.

`field_map` associe chaque champ de JobPayload à un chemin dans un élément de la réponse
(chemin pointé, ex: "company.name" ou "locations.0.name"). Champs reconnus :
external_id, title, description, url, company, company_logo, location, remote, contract,
experience_level, salary, salary_min, salary_max, salary_currency, published_at, skills,
application_url.

Clés d'API : jamais dans la configuration (stockée en base), toujours dans le .env, dans
une variable préfixée SOURCE_. La configuration ne contient que le NOM de la variable :

    "secret_query_params": {"app_id": "SOURCE_ADZUNA_APP_ID"}
    "secret_headers": {"Authorization": "Token {SOURCE_FINDWORK_API_KEY}"}

Exemple (API publique de Remote OK) :

    {
      "url": "https://remoteok.com/api",
      "field_map": {"title": "position", "company": "company", "location": "location",
                    "published_at": "date", "salary_min": "salary_min",
                    "salary_max": "salary_max", "application_url": "apply_url"},
      "defaults": {"salary_currency": "USD", "salary_period": "year"},
      "remote_only": true
    }

Exemple (API publique de Freelancer.com) :

    {
      "url": "https://www.freelancer.com/api/projects/0.1/projects/active/",
      "query_params": {"query": "python", "limit": "50", "job_details": "true"},
      "items_path": "result.projects",
      "field_map": {"title": "title", "description": "description", "published_at": "time_submitted",
                    "skills": "jobs"},
      "url_template": "https://www.freelancer.com/projects/{seo_url}",
      "extra_description_fields": {"Budget minimum": "budget.minimum", "Budget maximum": "budget.maximum",
                                   "Devise": "currency.code", "Type de projet": "type"},
      "defaults": {"contract": "Freelance"}
    }

Respectez toujours les conditions d'utilisation de l'API (quotas, attribution...).
"""

import json
from string import Formatter
from typing import Any

from pydantic import BaseModel, Field, HttpUrl, field_validator

from app.modules.scraping.adapters.common import (
    get_path,
    html_to_text,
    resolve_secret,
    secret_names,
)
from app.modules.scraping.base import FetchedPage, SourceAdapter
from app.modules.scraping.http import ScrapingError
from app.modules.scraping.registry import register_adapter
from app.shared.enums import SourceType

DEFAULT_FIELD_MAP = {
    "external_id": "id",
    "title": "title",
    "description": "description",
    "url": "url",
    "company": "company_name",
    "company_logo": "company_logo",
    "location": "candidate_required_location",
    "contract": "job_type",
    "salary": "salary",
    "published_at": "publication_date",
    "skills": "tags",
}


class JsonApiConfig(BaseModel):
    url: HttpUrl
    query_params: dict[str, str] = Field(default_factory=dict)
    items_path: str = Field(default="", description='Chemin de la liste d\'offres ("" = racine)')
    field_map: dict[str, str] = Field(default_factory=lambda: dict(DEFAULT_FIELD_MAP))
    url_template: str | None = Field(
        default=None,
        description='URL construite à partir de l\'élément, ex: "https://site/jobs/{slug}"',
    )
    defaults: dict[str, str] = Field(
        default_factory=dict,
        description="Valeurs fixes : contract, salary_currency, salary_period, location",
    )
    extra_description_fields: dict[str, str] = Field(
        default_factory=dict, description="Libellé -> chemin, ajoutés à la fin de la description"
    )
    secret_query_params: dict[str, str] = Field(
        default_factory=dict,
        description='Paramètre -> variable du .env, ex: {"app_key": "SOURCE_ADZUNA_APP_KEY"}',
    )
    secret_headers: dict[str, str] = Field(
        default_factory=dict,
        description='En-tête -> modèle, ex: {"Authorization": "Token {SOURCE_X}"}',
    )
    salary_multiplier: int = Field(
        default=1, ge=1, description="Ex : 1000 si l'API donne des milliers"
    )
    description_is_html: bool = True
    remote_only: bool = Field(default=False, description="Toutes les offres sont en télétravail")
    page_param: str | None = Field(default=None, description="Paramètre de pagination (ex: page)")
    max_pages: int = Field(default=1, ge=1, le=20)

    @field_validator("secret_query_params", "secret_headers")
    @classmethod
    def only_source_secrets(cls, value: dict[str, str]) -> dict[str, str]:
        for template in value.values():
            secret_names(template)  # lève une erreur si la variable n'est pas SOURCE_*
        return value


@register_adapter
class JsonApiAdapter(SourceAdapter):
    key = "json_api"
    description = "API JSON officielle (champs configurables via field_map)"
    source_types = frozenset({SourceType.API})
    config_model = JsonApiConfig
    respects_robots_txt = False
    config: JsonApiConfig

    def fetch(self) -> list[FetchedPage]:
        secret_params = {
            name: resolve_secret(template)
            for name, template in self.config.secret_query_params.items()
        }
        headers = {
            name: resolve_secret(template) for name, template in self.config.secret_headers.items()
        }
        pages: list[FetchedPage] = []
        for page_number in range(1, self.config.max_pages + 1):
            params = {**self.config.query_params, **secret_params}
            if self.config.page_param:
                params[self.config.page_param] = str(page_number)
            response = self.http.get_text(
                str(self.config.url), params=params, headers=headers or None
            )
            # URL sans paramètres : elle peut être enregistrée (erreurs) et ne doit contenir aucune clé.
            pages.append(
                FetchedPage(
                    url=str(self.config.url), content=response.text, content_type="application/json"
                )
            )
            if not self.config.page_param:
                break
        return pages

    def parse(self, page: FetchedPage) -> list[dict[str, Any]]:
        try:
            data = json.loads(page.content)
        except json.JSONDecodeError as exc:
            raise ScrapingError("The API did not return valid JSON") from exc
        items = get_path(data, self.config.items_path) if self.config.items_path else data
        if not isinstance(items, list):
            raise ScrapingError(f"No list found at items_path '{self.config.items_path}'")
        payloads = [self._to_payload(item) for item in items if isinstance(item, dict)]
        # Certains éléments ne sont pas des offres (ex: mention légale en tête de liste).
        return [payload for payload in payloads if payload["title"]]

    def _to_payload(self, item: dict[str, Any]) -> dict[str, Any]:
        field_map = {**DEFAULT_FIELD_MAP, **self.config.field_map}
        defaults = self.config.defaults

        def value(field: str) -> Any:
            return get_path(item, field_map.get(field))

        description = value("description")
        if self.config.description_is_html and isinstance(description, str):
            description = html_to_text(description)
        extras = [
            f"{label} : {extra}"
            for label, path in self.config.extra_description_fields.items()
            if (extra := get_path(item, path)) not in (None, "")
        ]
        if extras:
            description = "\n".join(filter(None, [description, "", *extras]))

        location = value("location") or defaults.get("location")
        payload: dict[str, Any] = {
            "external_id": value("external_id"),
            "title": value("title"),
            "description": description,
            "url": self._url(item) or value("url"),
            "company": {"name": value("company"), "logo_url": value("company_logo")},
            "location": {"raw": location if isinstance(location, str) else None},
            "contract": value("contract") or defaults.get("contract"),
            "experience_level": _as_text(value("experience_level")),
            "salary": self._salary(value, defaults),
            "published_at": value("published_at"),
            "skills": _skill_names(value("skills")),
            "application": {"url": value("application_url")},
            "raw_data": item,
        }
        remote = value("remote")
        if (
            self.config.remote_only
            or remote is True
            or (isinstance(remote, str) and "remote" in remote.lower())
        ):
            payload["location"]["remote"] = True
        elif isinstance(remote, str) and "hybrid" in remote.lower():
            payload["location"]["hybrid"] = True
        return payload

    def _url(self, item: dict[str, Any]) -> str | None:
        """URL construite avec url_template ("https://site/jobs/{slug}" -> clés de premier niveau)."""
        template = self.config.url_template
        if not template:
            return None
        names = [name for _, name, _, _ in Formatter().parse(template) if name]
        values = {name: item.get(name) for name in names}
        if any(value in (None, "") for value in values.values()):
            return None
        return template.format(**values)

    def _salary(self, value: Any, defaults: dict[str, str]) -> Any:
        multiplier = self.config.salary_multiplier
        minimum = (
            value("salary_min") * multiplier if value("salary_min") else None
        )  # 0 = non renseigné
        maximum = value("salary_max") * multiplier if value("salary_max") else None
        if minimum or maximum:
            return {
                "min": minimum,
                "max": maximum,
                "currency": value("salary_currency") or defaults.get("salary_currency"),
                "period": defaults.get("salary_period"),
            }
        return value("salary") or None


def _as_text(raw: Any) -> str | None:
    """Premier élément d'une liste, ou la valeur elle-même si c'est un texte."""
    if isinstance(raw, list):
        raw = raw[0] if raw else None
    return raw if isinstance(raw, str) else None


def _skill_names(raw: Any) -> list[str]:
    """Compétences : liste de textes, ou d'objets {"name": ...} / {"label": ...}."""
    if not isinstance(raw, list):
        return []
    names = []
    for item in raw:
        if isinstance(item, str):
            names.append(item)
        elif isinstance(item, dict) and isinstance(item.get("name") or item.get("label"), str):
            names.append(item.get("name") or item.get("label"))
    return [name for name in names if name.strip()]
