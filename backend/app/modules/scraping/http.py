"""Client HTTP "poli" utilisé par tous les adapters.

Ce client applique les règles de collecte du projet (RG-04, section 47) :
- il s'identifie honnêtement (SCRAPER_USER_AGENT) ;
- il respecte robots.txt quand l'adapter le demande (flux RSS, pages HTML) ;
- il limite son débit (rate_limit de la source) ;
- il refuse les adresses internes (protection SSRF) ;
- il S'ARRÊTE dès qu'une source refuse l'accès (401/403/429) ou affiche une protection
  anti-bot / CAPTCHA. Il n'existe AUCUN mécanisme de contournement, et il ne faut pas en ajouter.
"""

import logging
import time
import urllib.robotparser
from urllib.parse import urlsplit, urlunsplit

import httpx

from app.core.config import get_settings
from app.shared.utils import is_public_host

logger = logging.getLogger("app.scraping")

MAX_RESPONSE_BYTES = 5 * 1024 * 1024
ANTI_BOT_MARKERS = (
    "captcha",
    "cf-challenge",
    "are you a robot",
    "verify you are human",
    "access denied",
)


class ScrapingError(Exception):
    """Erreur de collecte (réseau, réponse invalide...)."""


class ScrapingBlockedError(ScrapingError):
    """La source refuse la collecte : on s'arrête, sans jamais tenter de contourner."""


class PoliteHttpClient:
    def __init__(
        self,
        rate_limit_per_minute: int | None = None,
        *,
        respect_robots_txt: bool = True,
        transport: httpx.BaseTransport | None = None,
    ) -> None:
        settings = get_settings()
        self.user_agent = settings.SCRAPER_USER_AGENT
        self.respect_robots_txt = respect_robots_txt
        self.allow_private_urls = settings.ALLOW_PRIVATE_SOURCE_URLS
        rate = rate_limit_per_minute or settings.SCRAPER_DEFAULT_RATE_LIMIT
        self.min_interval = 60.0 / rate
        self._last_request_at = 0.0
        self._robots: dict[str, urllib.robotparser.RobotFileParser | None] = {}
        self.requests_made = 0
        self._client = httpx.Client(
            timeout=settings.SCRAPER_TIMEOUT_SECONDS,
            headers={"User-Agent": self.user_agent},
            follow_redirects=True,
            max_redirects=5,
            transport=transport,
            # Vérifié aussi pour chaque redirection : une redirection vers une IP interne est refusée.
            event_hooks={"request": [self._check_request_target]},
        )

    def __enter__(self) -> "PoliteHttpClient":
        return self

    def __exit__(self, *_args: object) -> None:
        self.close()

    def close(self) -> None:
        self._client.close()

    def get_text(
        self,
        url: str,
        params: dict[str, str] | None = None,
        headers: dict[str, str] | None = None,
    ) -> httpx.Response:
        """GET poli : contrôle robots.txt, attend le délai minimum, vérifie la réponse."""
        if self.respect_robots_txt and not self.is_allowed_by_robots(url):
            raise ScrapingBlockedError(f"robots.txt disallows {url}")
        self._wait_for_rate_limit()
        try:
            response = self._client.get(url, params=params, headers=headers)
        except httpx.HTTPError as exc:
            raise ScrapingError(f"Request failed: {type(exc).__name__}") from exc
        self.requests_made += 1
        return self._checked(response, url)

    def post_form(self, url: str, data: dict[str, str]) -> httpx.Response:
        """POST de formulaire (ex : obtention d'un token OAuth d'une API officielle)."""
        self._wait_for_rate_limit()
        try:
            response = self._client.post(url, data=data)
        except httpx.HTTPError as exc:
            raise ScrapingError(f"Request failed: {type(exc).__name__}") from exc
        self.requests_made += 1
        return self._checked(response, url)

    def _checked(self, response: httpx.Response, url: str) -> httpx.Response:
        """Arrêt immédiat si la source refuse l'accès ou affiche une protection anti-bot."""
        if response.status_code in {401, 403, 429}:
            raise ScrapingBlockedError(f"Source refused access (HTTP {response.status_code})")
        if response.status_code >= 400:
            raise ScrapingError(f"HTTP {response.status_code} for {url}")
        if len(response.content) > MAX_RESPONSE_BYTES:
            raise ScrapingError("Response too large")
        content_type = response.headers.get("content-type", "")
        if "html" in content_type and self._looks_like_anti_bot_page(response.text):
            raise ScrapingBlockedError("Anti-bot protection detected: collection stopped")
        return response

    def is_allowed_by_robots(self, url: str) -> bool:
        parts = urlsplit(url)
        origin = f"{parts.scheme}://{parts.netloc}"
        if origin not in self._robots:
            self._robots[origin] = self._load_robots(origin)
        parser = self._robots[origin]
        return True if parser is None else parser.can_fetch(self.user_agent, url)

    # --- Interne ---

    def _load_robots(self, origin: str) -> urllib.robotparser.RobotFileParser | None:
        """Charge robots.txt. None = pas de restriction (fichier absent)."""
        robots_url = urlunsplit((*urlsplit(origin)[:2], "/robots.txt", "", ""))
        parser = urllib.robotparser.RobotFileParser(robots_url)
        try:
            self._wait_for_rate_limit()
            response = self._client.get(robots_url)
            self.requests_made += 1
        except httpx.HTTPError:
            parser.parse(["User-agent: *", "Disallow: /"])  # prudence : serveur injoignable
            return parser
        if response.status_code in {401, 403} or response.status_code >= 500:
            parser.parse(["User-agent: *", "Disallow: /"])  # accès refusé ou serveur en erreur
            return parser
        if response.status_code >= 400:
            return None
        parser.parse(response.text.splitlines())
        return parser

    def _wait_for_rate_limit(self) -> None:
        elapsed = time.monotonic() - self._last_request_at
        if elapsed < self.min_interval:
            time.sleep(self.min_interval - elapsed)
        self._last_request_at = time.monotonic()

    def _check_request_target(self, request: httpx.Request) -> None:
        if request.url.scheme not in {"http", "https"}:
            raise ScrapingError("Only http(s) URLs are allowed")
        host = request.url.host
        if not self.allow_private_urls and not is_public_host(host):
            logger.warning("Blocked request to a non-public address", extra={"host": host})
            raise ScrapingBlockedError(f"URL host is not a public address: {host}")

    @staticmethod
    def _looks_like_anti_bot_page(html: str) -> bool:
        head = html[:5000].lower()
        return any(marker in head for marker in ANTI_BOT_MARKERS)
