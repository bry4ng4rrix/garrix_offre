"""Interface commune des adapters de source.

Un adapter sait faire DEUX choses pour UNE famille de sources :
1. `fetch()` : récupérer les données brutes (pages HTML, flux RSS, JSON d'API) ;
2. `parse()` : découper ces données brutes en offres au format `JobPayload` (dict).

Tout le reste (normalisation, validation, déduplication, enregistrement, matching,
notification) est commun à toutes les sources et géré par le pipeline.

Pour créer un adapter : voir scraping/adapters/example_rss.py et le README
("Comment ajouter une nouvelle source").
"""

import uuid
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, ClassVar

from pydantic import BaseModel

from app.modules.scraping.http import PoliteHttpClient
from app.shared.enums import SourceType


@dataclass(frozen=True)
class SourceContext:
    """Copie des informations de la source (l'adapter n'accède jamais à la base)."""

    source_id: uuid.UUID
    name: str
    base_url: str | None
    configuration: dict[str, Any]
    rate_limit: int | None = None


@dataclass
class FetchedPage:
    """Réponse brute d'une source (résultat de l'étape FETCH)."""

    url: str
    content: str
    content_type: str | None = None
    metadata: dict[str, Any] = field(default_factory=dict)


class SourceAdapter(ABC):
    """Classe mère de tous les adapters."""

    key: ClassVar[str]
    description: ClassVar[str]
    source_types: ClassVar[frozenset[SourceType]]
    config_model: ClassVar[type[BaseModel]]
    # robots.txt s'applique aux robots d'exploration (RSS, HTML). Une API officielle est
    # encadrée par ses propres conditions d'utilisation.
    respects_robots_txt: ClassVar[bool] = True

    def __init__(self, context: SourceContext, http: PoliteHttpClient) -> None:
        self.context = context
        self.http = http
        self.config = self.config_model.model_validate(context.configuration)

    @abstractmethod
    def fetch(self) -> list[FetchedPage]:
        """FETCH : récupère les données brutes de la source."""

    @abstractmethod
    def parse(self, page: FetchedPage) -> list[dict[str, Any]]:
        """PARSE : transforme une page brute en offres (dicts au format JobPayload)."""

    def enrich(self, job: dict[str, Any]) -> dict[str, Any]:
        """Étape optionnelle : compléter une offre (ex: page de détail). Par défaut : rien."""
        return job
