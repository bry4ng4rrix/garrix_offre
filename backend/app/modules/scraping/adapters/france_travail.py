"""Adapter "france_travail_api" : API officielle France Travail "Offres d'emploi v2".

Accès gratuit : créez une application sur https://francetravail.io, ajoutez-lui l'API
"Offres d'emploi v2", puis renseignez FRANCE_TRAVAIL_CLIENT_ID et FRANCE_TRAVAIL_CLIENT_SECRET
dans le .env (les secrets ne sont jamais stockés dans la configuration de la source).

Exemple de configuration :

    {
      "keywords": "développeur python",
      "departement": "75",
      "contract_types": "CDI,CDD",
      "published_since_days": 7
    }
"""

import json
import re
from typing import Any, Literal

from pydantic import BaseModel, Field

from app.core.config import get_settings
from app.modules.scraping.base import FetchedPage, SourceAdapter
from app.modules.scraping.http import ScrapingError
from app.modules.scraping.registry import register_adapter
from app.shared.enums import ContactSource, SourceType

TOKEN_URL = (  # noqa: S105 - URL publique du service OAuth, pas un secret
    "https://entreprise.francetravail.fr/connexion/oauth2/access_token?realm=%2Fpartenaire"
)
SEARCH_URL = "https://api.francetravail.io/partenaire/offresdemploi/v2/offres/search"
OFFER_PAGE_URL = "https://candidat.francetravail.fr/offres/recherche/detail/{id}"
SCOPE = "api_offresdemploiv2 o2dsoffre"
PAGE_SIZE = 150  # maximum autorisé par l'API

# Codes de contrat de l'API -> libellés reconnus par nos types de contrat.
CONTRACT_CODES = {"CDI": "CDI", "CDD": "CDD", "LIB": "Freelance", "MIS": "Intérim"}
_ARRONDISSEMENT = re.compile(r"\s+\d+(er|e|ème)?\s+arrondissement$", re.IGNORECASE)


class FranceTravailConfig(BaseModel):
    keywords: str = Field(default="développeur", max_length=200, description="Mots-clés (motsCles)")
    departement: str | None = Field(default=None, max_length=5, description="Ex : 75")
    region: str | None = Field(default=None, max_length=5, description="Code région INSEE")
    contract_types: str | None = Field(
        default=None, description="Codes séparés par des virgules : CDI,CDD,LIB"
    )
    published_since_days: Literal[1, 3, 7, 14, 31] = 7
    max_pages: int = Field(default=1, ge=1, le=5)


@register_adapter
class FranceTravailAdapter(SourceAdapter):
    key = "france_travail_api"
    description = "API officielle France Travail (Offres d'emploi v2, OAuth2)"
    source_types = frozenset({SourceType.API})
    config_model = FranceTravailConfig
    respects_robots_txt = False
    config: FranceTravailConfig

    def fetch(self) -> list[FetchedPage]:
        headers = {"Authorization": f"Bearer {self._access_token()}", "Accept": "application/json"}
        params = {
            "motsCles": self.config.keywords,
            "publieeDepuis": str(self.config.published_since_days),
            "sort": "1",  # les plus récentes d'abord
        }
        if self.config.departement:
            params["departement"] = self.config.departement
        if self.config.region:
            params["region"] = self.config.region
        if self.config.contract_types:
            params["typeContrat"] = self.config.contract_types

        pages: list[FetchedPage] = []
        for page_number in range(self.config.max_pages):
            start = page_number * PAGE_SIZE
            params["range"] = f"{start}-{start + PAGE_SIZE - 1}"
            response = self.http.get_text(SEARCH_URL, params=params, headers=headers)
            if response.status_code == 204:  # aucun résultat
                break
            pages.append(
                FetchedPage(url=SEARCH_URL, content=response.text, content_type="application/json")
            )
            if response.status_code != 206:  # 206 = résultats partiels, il en reste
                break
        return pages

    def parse(self, page: FetchedPage) -> list[dict[str, Any]]:
        try:
            offers = json.loads(page.content).get("resultats", [])
        except (json.JSONDecodeError, AttributeError) as exc:
            raise ScrapingError("Unexpected France Travail response") from exc
        return [self._to_payload(offer) for offer in offers if offer.get("intitule")]

    def _access_token(self) -> str:
        settings = get_settings()
        if not settings.FRANCE_TRAVAIL_CLIENT_ID or settings.FRANCE_TRAVAIL_CLIENT_SECRET is None:
            raise ScrapingError(
                "FRANCE_TRAVAIL_CLIENT_ID / FRANCE_TRAVAIL_CLIENT_SECRET are not configured"
            )
        response = self.http.post_form(
            TOKEN_URL,
            {
                "grant_type": "client_credentials",
                "client_id": settings.FRANCE_TRAVAIL_CLIENT_ID,
                "client_secret": settings.FRANCE_TRAVAIL_CLIENT_SECRET.get_secret_value(),
                "scope": SCOPE,
            },
        )
        token = response.json().get("access_token")
        if not token:
            raise ScrapingError("France Travail did not return an access token")
        return str(token)

    @staticmethod
    def _to_payload(offer: dict[str, Any]) -> dict[str, Any]:
        company = offer.get("entreprise") or {}
        contact = offer.get("contact") or {}
        place = (offer.get("lieuTravail") or {}).get("libelle")
        if place:
            place = _ARRONDISSEMENT.sub(
                "", place
            )  # "75 - Paris 1er Arrondissement" -> "75 - Paris"
        contract = CONTRACT_CODES.get(offer.get("typeContrat", ""), offer.get("typeContratLibelle"))
        if offer.get("alternance"):
            contract = "Alternance"
        recruiter = None
        if contact.get("nom") or contact.get("courriel"):
            recruiter = {
                "name": contact.get("nom"),
                "email": contact.get("courriel"),
                "contact_source": ContactSource.API.value,
            }
        offer_url = (offer.get("origineOffre") or {}).get("urlOrigine") or OFFER_PAGE_URL.format(
            id=offer["id"]
        )
        return {
            "external_id": offer.get("id"),
            "title": offer.get("intitule"),
            "description": offer.get("description"),
            "url": offer_url,
            "company": {
                "name": company.get("nom"),
                "description": company.get("description"),
                "logo_url": company.get("logo"),
                "website": company.get("url"),
            },
            "recruiter": recruiter,
            "location": {"raw": f"{place}, France" if place else None, "country": "France"},
            "contract": {"type": contract, "work_time": offer.get("dureeTravailLibelleConverti")},
            "salary": {"raw": (offer.get("salaire") or {}).get("libelle")},
            "experience_level": offer.get("experienceLibelle"),
            "languages": [item.get("libelle", "") for item in offer.get("langues") or []],
            "application": {"url": contact.get("urlPostulation"), "email": contact.get("courriel")},
            "published_at": offer.get("dateCreation"),
            "raw_data": offer,
        }
