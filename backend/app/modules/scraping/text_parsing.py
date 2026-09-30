"""Lecture d'informations dans du texte libre (utilisé par la normalisation).

Toutes les fonctions sont pures et testées dans tests/unit/test_text_parsing.py.
Elles ne devinent rien : si une information n'est pas clairement présente, elles
retournent None.
"""

import re
from dataclasses import dataclass

from app.shared.geo import (
    HYBRID_KEYWORDS,
    REMOTE_KEYWORDS,
    contains_keyword,
    detect_country,
    known_country,
)
from app.shared.utils import normalize_text, strip_accents

# --- Salaire ---

CURRENCIES = {
    "€": "EUR", "eur": "EUR", "euro": "EUR", "euros": "EUR", "$": "USD", "usd": "USD",
    "£": "GBP", "gbp": "GBP", "chf": "CHF", "cad": "CAD", "mga": "MGA", "ariary": "MGA", "ar": "MGA",
}  # fmt: skip
PERIODS = {
    "year": ("par an", "/an", "an ", "annuel", "annuelle", "brut annuel", "per year", "/year", "a year",
             "yearly", "annual", "per annum", "p.a", "k€/an"),
    "month": ("par mois", "/mois", "mensuel", "mensuelle", "per month", "/month", "a month", "monthly"),
    "day": ("par jour", "/jour", "jour", "tjm", "per day", "/day", "a day", "daily"),
    "hour": ("par heure", "/heure", "/h", "horaire", "per hour", "/hour", "an hour", "hourly"),
}  # fmt: skip
SALARY_KEYWORDS = ("salaire", "salary", "remuneration", "package", "tjm", "compensation")
SALARY_SEGMENT_LENGTH = 60
_SEGMENT_END = re.compile(r"[;\n]|\.\s|,\s+(?=[^\d\s])")

_NUMBER = re.compile(r"(\d{1,3}(?:[   .,]\d{3})+|\d+(?:[.,]\d+)?)\s*(k)?(?![a-z])", re.IGNORECASE)


@dataclass(frozen=True)
class SalaryInfo:
    minimum: int | None = None
    maximum: int | None = None
    currency: str | None = None
    period: str | None = None


def _to_number(raw: str, has_k: bool) -> float:
    cleaned = raw.replace(" ", " ").replace(" ", " ")
    if re.fullmatch(r"\d{1,3}(?:[ .,]\d{3})+", cleaned):
        value = float(re.sub(r"[ .,]", "", cleaned))  # séparateurs de milliers
    else:
        value = float(cleaned.replace(",", "."))
    return value * 1000 if has_k else value


def _detect_currency(text: str) -> str | None:
    lowered = text.lower()
    for symbol in ("€", "$", "£"):
        if symbol in lowered:
            return CURRENCIES[symbol]
    words = set(re.findall(r"[a-z]+", strip_accents(lowered)))
    for word, code in CURRENCIES.items():
        if word.isalpha() and word in words:
            return code
    return None


def _detect_period(text: str) -> str | None:
    lowered = f" {strip_accents(text.lower())} "
    for period, markers in PERIODS.items():
        if any(marker in lowered for marker in markers):
            return period
    return None


def _period_from_amount(amount: float, currency: str | None) -> str | None:
    """Période probable d'après le montant (uniquement pour les devises connues)."""
    if currency in {"EUR", "USD", "GBP", "CHF", "CAD"}:
        if amount >= 10_000:
            return "year"
        if amount >= 1_000:
            return "month"
        if amount >= 100:
            return "day"
        return "hour"
    if currency == "MGA":
        return "year" if amount >= 10_000_000 else "month"
    return None


def parse_salary(text: str | None) -> SalaryInfo:
    """Ex : "35k - 45k € / an" -> SalaryInfo(35000, 45000, "EUR", "year")."""
    if not text:
        return SalaryInfo()
    matches = _NUMBER.findall(text)
    # "40 - 50 k€" : le "k" final s'applique aussi au premier nombre.
    shared_k = any(k for _, k in matches)
    amounts = [
        _to_number(number, bool(k) or (shared_k and _to_number(number, False) < 1000))
        for number, k in matches
    ]
    amounts = [amount for amount in amounts if amount >= 1]
    if not amounts:
        return SalaryInfo()
    low, high = min(amounts[:2]), max(amounts[:2])
    currency = _detect_currency(text)
    period = _detect_period(text) or _period_from_amount(high, currency)
    return SalaryInfo(int(low), int(high) if high != low else int(low), currency, period)


def find_salary_in_text(text: str | None) -> SalaryInfo:
    """Cherche une ligne de salaire explicite dans une description (mot-clé + devise)."""
    if not text:
        return SalaryInfo()
    for line in text.splitlines():
        normalized = strip_accents(line.lower())
        for keyword in SALARY_KEYWORDS:
            position = normalized.find(keyword)
            if position == -1:
                continue
            # On n'analyse que le passage qui suit le mot-clé ("Salaire : 45 - 55 k€ par an").
            segment = line[position : position + SALARY_SEGMENT_LENGTH]
            segment = _SEGMENT_END.split(segment)[0]  # s'arrête à la fin de la phrase
            if _detect_currency(segment):
                info = parse_salary(segment)
                if info.minimum:
                    return info
    return SalaryInfo()


# --- Localisation ---


@dataclass(frozen=True)
class LocationInfo:
    city: str | None = None
    country: str | None = None
    remote: bool = False
    hybrid: bool = False


_LOCATION_SEPARATORS = re.compile(r"[,/|;–-]|\s\(|\)")


def parse_location(raw: str | None) -> LocationInfo:
    """Ex : "Paris, France" -> ville + pays ; "Remote" -> télétravail."""
    if not raw or not raw.strip():
        return LocationInfo()
    remote = contains_keyword(raw, REMOTE_KEYWORDS) or normalize_text(raw) in {
        "worldwide",
        "anywhere",
    }
    hybrid = contains_keyword(raw, HYBRID_KEYWORDS)
    city = country = None
    for token in _LOCATION_SEPARATORS.split(raw):
        part = re.sub(r"\b(only|uniquement|seulement)\b", "", token, flags=re.IGNORECASE).strip()
        if not part or part.isdigit() or contains_keyword(part, REMOTE_KEYWORDS + HYBRID_KEYWORDS):
            continue
        if known_country(part):
            country = country or known_country(part)
        elif city is None and normalize_text(part) not in {
            "worldwide",
            "anywhere",
            "europe",
            "emea",
        }:
            city = part
    return LocationInfo(
        city=city, country=country or detect_country(raw), remote=remote, hybrid=hybrid
    )


# --- Expérience, temps de travail, langues ---

_YEARS = re.compile(
    r"(\d{1,2})\s*\+?\s*(?:a|à|-|to)?\s*(?:\d{1,2}\s*)?(?:ans|annees|années|years?|yrs)\b"
    r"(?:\s+(?:d['’]|of\s+)?(?:experience|expérience))?",
    re.IGNORECASE,
)


def parse_min_years(text: str | None) -> int | None:
    """Ex : "3+ years of experience" -> 3 ; "5 ans d'expérience" -> 5."""
    if not text:
        return None
    for match in _YEARS.finditer(text):
        window = strip_accents(text[max(0, match.start() - 60) : match.end() + 40].lower())
        if "experience" in window:
            years = int(match.group(1))
            if 0 < years <= 30:
                return years
    return None


def detect_work_time(text: str | None) -> str | None:
    normalized = f" {normalize_text(text)} "
    if any(marker in normalized for marker in (" part time ", " temps partiel ", " mi temps ")):
        return "part_time"
    if any(marker in normalized for marker in (" full time ", " temps plein ", " temps complet ")):
        return "full_time"
    return None


LANGUAGE_NAMES = {
    "fr": ("francais", "french"),
    "en": ("anglais", "english"),
    "es": ("espagnol", "spanish"),
    "de": ("allemand", "german"),
    "it": ("italien", "italian"),
    "pt": ("portugais", "portuguese"),
    "mg": ("malagasy", "malgache"),
    "ar": ("arabe", "arabic"),
    "zh": ("chinois", "chinese", "mandarin"),
}
_FRENCH_WORDS = {
    "le",
    "la",
    "les",
    "des",
    "et",
    "vous",
    "nous",
    "une",
    "pour",
    "avec",
    "dans",
    "sur",
}
_ENGLISH_WORDS = {
    "the",
    "and",
    "you",
    "we",
    "with",
    "for",
    "our",
    "are",
    "will",
    "your",
    "this",
    "in",
}


def language_code(value: str) -> str | None:
    """ "French" / "français" / "FR" -> "fr"."""
    normalized = normalize_text(value)
    if normalized in LANGUAGE_NAMES:
        return normalized
    for code, names in LANGUAGE_NAMES.items():
        if normalized in names:
            return code
    return None


def detect_languages(text: str | None) -> list[str]:
    """Langue principale de la description + langues explicitement demandées."""
    if not text:
        return []
    words = normalize_text(text).split()
    french = sum(1 for word in words if word in _FRENCH_WORDS)
    english = sum(1 for word in words if word in _ENGLISH_WORDS)
    codes: set[str] = set()
    if max(french, english) >= 3:
        codes.add("fr" if french >= english else "en")
    padded = f" {' '.join(words)} "
    for code, names in LANGUAGE_NAMES.items():
        for name in names:
            if (
                f" {name} courant " in padded
                or f" fluent {name} " in padded
                or f" {name} fluent " in padded
            ):
                codes.add(code)
            if f" {name} required " in padded or f" {name} exige " in padded:
                codes.add(code)
    return sorted(codes)
