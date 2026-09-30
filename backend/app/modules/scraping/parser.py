"""Étape PARSE du pipeline : pages brutes -> offres au format JobPayload."""

import logging
from dataclasses import dataclass, field

from pydantic import ValidationError

from app.modules.scraping.base import FetchedPage, SourceAdapter
from app.modules.scraping.http import ScrapingBlockedError, ScrapingError
from app.modules.scraping.schemas import JobPayload

logger = logging.getLogger("app.scraping")


@dataclass
class ParseResult:
    jobs: list[JobPayload] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)


class ParserService:
    """Découpe les pages en offres, les complète si besoin (enrich) et écarte les illisibles."""

    def parse(self, adapter: SourceAdapter, pages: list[FetchedPage], max_jobs: int) -> ParseResult:
        result = ParseResult()
        can_enrich = True
        for page in pages:
            try:
                items = adapter.parse(page)
            except ScrapingError as exc:
                result.errors.append(f"{page.url}: {exc}")
                continue
            for item in items:
                if len(result.jobs) >= max_jobs:
                    result.errors.append(f"Limit of {max_jobs} jobs per run reached")
                    return result
                if can_enrich:
                    try:
                        item = adapter.enrich(item)
                    except ScrapingBlockedError as exc:
                        # La source refuse : on arrête les requêtes supplémentaires.
                        can_enrich = False
                        result.errors.append(f"Enrichment stopped: {exc}")
                    except ScrapingError as exc:
                        result.errors.append(f"Enrichment failed: {exc}")
                try:
                    result.jobs.append(JobPayload.model_validate(item))
                except ValidationError as exc:
                    fields = ", ".join(".".join(str(p) for p in err["loc"]) for err in exc.errors())
                    result.errors.append(f"Unreadable job ({fields})")
        logger.info("Jobs parsed", extra={"jobs": len(result.jobs), "errors": len(result.errors)})
        return result
