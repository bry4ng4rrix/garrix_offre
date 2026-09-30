"""Offres reçues par alertes email.

Beaucoup de sites (LinkedIn, Indeed, APEC, Welcome to the Jungle, Malt...) interdisent la
collecte automatique de leurs pages et n'ont pas d'API ouverte, mais proposent des ALERTES
EMAIL : vous choisissez de recevoir leurs offres dans votre boîte mail.

Fonctionnement :
1. vous créez des alertes sur ces sites (avec votre adresse email) ;
2. le workflow n8n "job-alerts-email" lit ces emails (IMAP) et les transmet tels quels à
   POST /webhooks/n8n/job-alert-email ;
3. ce module retrouve la source (domaine de l'expéditeur) et extrait les offres (titre + lien) ;
4. les offres suivent le pipeline habituel (déduplication, matching, notifications).

Aucune page du site n'est visitée : seul le contenu de l'email reçu est lu.
"""

import re
from dataclasses import dataclass
from typing import Any
from urllib.parse import urlsplit

from bs4 import BeautifulSoup

from app.modules.sources.models import Source
from app.shared.utils import canonical_url, email_domain, normalize_text, url_domain

# Un lien d'offre contient généralement l'un de ces mots dans son URL.
JOB_LINK_HINTS = (
    "job", "offre", "emploi", "annonce", "mission", "project", "projet", "career", "poste",
    "vacanc", "clk", "view",
)  # fmt: skip
# Liens de service à ignorer (désinscription, paramètres, aide...).
IGNORED_LINK_WORDS = (
    "unsubscribe", "desinscri", "desabonn", "preference", "settings", "parametre", "help", "aide",
    "privacy", "confidentialite", "login", "connexion", "alert", "alerte", "search", "recherche",
    "app-store", "play.google", "apps.apple", "browser", "navigateur",
)  # fmt: skip
GENERIC_LINK_TEXTS = {
    "voir", "voir l offre", "voir les offres", "postuler", "apply", "view job", "view all jobs",
    "see all jobs", "toutes les offres", "voir plus", "see more", "en savoir plus", "learn more",
}  # fmt: skip
MIN_TITLE_LENGTH = 4
MAX_TITLE_LENGTH = 150
MAX_JOBS_PER_EMAIL = 50


@dataclass
class AlertExtraction:
    source: Source | None
    jobs: list[dict[str, Any]]


def _domains_of(source: Source) -> set[str]:
    domains = {url_domain(source.base_url)}
    domains.update(source.configuration.get("alert_link_domains", []))
    return {domain.lower() for domain in domains if domain}


def _same_site(host: str | None, domains: set[str]) -> bool:
    return bool(host) and any(host == domain or host.endswith(f".{domain}") for domain in domains)  # type: ignore[union-attr]


class JobAlertEmailParser:
    """Extrait les offres d'un email d'alerte et retrouve la source correspondante."""

    def __init__(self, sources: list[Source]) -> None:
        self.sources = sources

    def find_source(self, sender_email: str, source_name: str | None = None) -> Source | None:
        if source_name:
            return next((source for source in self.sources if source.name == source_name), None)
        sender = email_domain(sender_email)
        for source in self.sources:
            if _same_site(sender, _domains_of(source)):
                return source
        return None

    def extract(
        self, sender_email: str, html: str | None, text: str | None, source_name: str | None = None
    ) -> AlertExtraction:
        source = self.find_source(sender_email, source_name)
        domains = _domains_of(source) if source else {email_domain(sender_email) or ""}
        jobs: dict[str, dict[str, Any]] = {}
        for title, href in self._links(html, text):
            url = canonical_url(href)
            if not url or url in jobs or not _same_site(url_domain(url), domains):
                continue
            path = urlsplit(url).path.lower()  # le chemin seulement : la query contient du tracking
            if any(word in path for word in IGNORED_LINK_WORDS):
                continue
            if not any(hint in path for hint in JOB_LINK_HINTS):
                continue
            jobs[url] = {
                "title": title,
                "url": url,
                "raw_data": {"alert_sender": sender_email, "link_text": title},
            }
            if len(jobs) >= MAX_JOBS_PER_EMAIL:
                break
        return AlertExtraction(source=source, jobs=list(jobs.values()))

    @staticmethod
    def _links(html: str | None, text: str | None) -> list[tuple[str, str]]:
        links: list[tuple[str, str]] = []
        if html:
            soup = BeautifulSoup(html, "html.parser")
            for anchor in soup.find_all("a", href=True):
                title = " ".join(anchor.get_text(" ", strip=True).split())
                href = anchor.get("href")
                if isinstance(href, str) and _looks_like_title(title):
                    links.append((title, href))
        elif text:
            # Email texte : "Titre du poste\nhttps://..." -> la ligne précédant l'URL est le titre.
            lines = [line.strip() for line in text.splitlines() if line.strip()]
            for index, line in enumerate(lines):
                match = re.search(r"https?://\S+", line)
                if match and index > 0 and _looks_like_title(lines[index - 1]):
                    links.append((lines[index - 1], match.group(0)))
        return links


def _looks_like_title(text: str) -> bool:
    if not MIN_TITLE_LENGTH <= len(text) <= MAX_TITLE_LENGTH:
        return False
    normalized = normalize_text(text)
    return bool(normalized) and normalized not in GENERIC_LINK_TEXTS and not text.startswith("http")
