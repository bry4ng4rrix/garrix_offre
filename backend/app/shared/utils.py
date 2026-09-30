"""Petites fonctions utilitaires sans dépendance à la base de données."""

import ipaddress
import re
import socket
import unicodedata
from datetime import UTC, datetime
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit


def utcnow() -> datetime:
    """Date/heure courante en UTC (toujours utiliser cette fonction, RG-17)."""
    return datetime.now(UTC)


def strip_accents(text: str) -> str:
    normalized = unicodedata.normalize("NFKD", text)
    return "".join(char for char in normalized if not unicodedata.combining(char))


_NON_ALNUM = re.compile(r"[^a-z0-9+#]+")
# Marqueurs de genre fréquents dans les titres d'offres : "(H/F)", "F/H", "m/w/d"...
_GENDER_MARKERS = re.compile(
    r"\(?\b(h\s*/\s*f|f\s*/\s*h|m\s*/\s*f|f\s*/\s*m|m\s*/\s*w\s*/\s*d)\b\)?"
)


def normalize_text(text: str | None) -> str:
    """Forme comparable d'un texte : minuscules, sans accents ni ponctuation.

    >>> normalize_text("Développeur Full-Stack (H/F)")
    'developpeur full stack'
    """
    if not text:
        return ""
    lowered = strip_accents(text).lower()
    lowered = _GENDER_MARKERS.sub(" ", lowered)
    return _NON_ALNUM.sub(" ", lowered).strip()


def slugify(text: str) -> str:
    return normalize_text(text).replace(" ", "_")


# Suffixes juridiques retirés pour comparer les noms d'entreprises.
_COMPANY_SUFFIXES = {
    "sas", "sasu", "sarl", "sa", "eurl", "sci", "inc", "ltd", "llc", "gmbh", "bv", "srl",
    "corp", "corporation", "limited", "group", "groupe",
}  # fmt: skip


def normalize_company_name(name: str | None) -> str:
    words = [word for word in normalize_text(name).split() if word not in _COMPANY_SUFFIXES]
    return " ".join(words)


_TRACKING_PARAMS = {"ref", "source", "fbclid", "gclid", "trk", "trackingid", "refid", "src"}


def canonical_url(url: str | None) -> str | None:
    """Normalise une URL pour la déduplication (host en minuscules, sans tracking ni fragment)."""
    if not url:
        return None
    try:
        parts = urlsplit(url.strip())
    except ValueError:
        return None
    if parts.scheme not in {"http", "https"} or not parts.netloc:
        return None
    query = [
        (key, value)
        for key, value in parse_qsl(parts.query, keep_blank_values=False)
        if not key.lower().startswith("utm_") and key.lower() not in _TRACKING_PARAMS
    ]
    path = parts.path.rstrip("/") or "/"
    return urlunsplit(
        (parts.scheme.lower(), parts.netloc.lower(), path, urlencode(sorted(query)), "")
    )


def url_domain(url: str | None) -> str | None:
    if not url:
        return None
    try:
        host = urlsplit(url if "://" in url else f"https://{url}").hostname
    except ValueError:
        return None
    if not host:
        return None
    return host.lower().removeprefix("www.")


def email_domain(email: str | None) -> str | None:
    if not email or "@" not in email:
        return None
    return email.rsplit("@", 1)[1].strip().lower()


def is_public_host(hostname: str) -> bool:
    """Vrai si toutes les IP du nom d'hôte sont publiques (protection SSRF).

    Empêche une source configurée de faire appeler au backend une adresse interne
    (base de données, métadonnées cloud, réseau Docker...).
    """
    try:
        addresses = {info[4][0] for info in socket.getaddrinfo(hostname, None)}
    except (socket.gaierror, UnicodeError):
        return False
    for address in addresses:
        ip = ipaddress.ip_address(str(address).split("%", 1)[0])
        if not ip.is_global:
            return False
    return bool(addresses)


def truncate(text: str | None, length: int) -> str | None:
    if text is None or len(text) <= length:
        return text
    return text[: length - 1].rstrip() + "…"
