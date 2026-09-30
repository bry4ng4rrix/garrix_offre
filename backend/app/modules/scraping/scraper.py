"""Étape FETCH du pipeline : prépare l'adapter d'une source et récupère les données brutes."""

import logging

import httpx

from app.core.exceptions import BusinessRuleError
from app.modules.scraping.base import FetchedPage, SourceAdapter, SourceContext
from app.modules.scraping.http import PoliteHttpClient
from app.modules.scraping.registry import get_adapter_class
from app.modules.sources.models import Source
from app.shared.enums import SourceType

logger = logging.getLogger("app.scraping")


class ScraperService:
    """Crée l'adapter adapté à une source et lance la récupération des données brutes."""

    def __init__(self, transport: httpx.BaseTransport | None = None) -> None:
        # `transport` permet aux tests de simuler les réponses HTTP.
        self.transport = transport

    def build_adapter(self, source: Source) -> SourceAdapter:
        if not source.adapter:
            raise BusinessRuleError("This source has no adapter", code="SOURCE_NOT_COLLECTABLE")
        adapter_class = get_adapter_class(source.adapter)
        if adapter_class is None:
            raise BusinessRuleError("Unknown adapter", code="UNKNOWN_ADAPTER")
        if source.type == SourceType.HTML and not source.terms_reviewed:
            raise BusinessRuleError(
                "HTML collection requires terms_reviewed=true (the site's terms must allow it)",
                code="SOURCE_TERMS_NOT_REVIEWED",
            )
        http = PoliteHttpClient(
            source.rate_limit,
            respect_robots_txt=adapter_class.respects_robots_txt,
            transport=self.transport,
        )
        context = SourceContext(
            source_id=source.id,
            name=source.name,
            base_url=source.base_url,
            configuration=source.configuration,
            rate_limit=source.rate_limit,
        )
        return adapter_class(context, http)

    def fetch(self, adapter: SourceAdapter) -> list[FetchedPage]:
        pages = adapter.fetch()
        logger.info(
            "Source fetched",
            extra={
                "source": adapter.context.name,
                "pages": len(pages),
                "requests": adapter.http.requests_made,
            },
        )
        return pages
