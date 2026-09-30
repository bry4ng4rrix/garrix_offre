"""Normalisation des pays et des localisations.

Le but est de pouvoir comparer "FR", "france" et "France" : tout est ramené à un nom
canonique en français. Pour ajouter un pays, complétez `COUNTRY_ALIASES`.
"""

from app.shared.utils import normalize_text

# nom canonique -> alias reconnus (déjà normalisés : minuscules, sans accents)
COUNTRY_ALIASES: dict[str, set[str]] = {
    "France": {"france", "fr", "fra"},
    "Madagascar": {"madagascar", "mg", "mdg"},
    "Belgique": {"belgique", "belgium", "be", "bel"},
    "Suisse": {"suisse", "switzerland", "ch", "che", "schweiz"},
    "Luxembourg": {"luxembourg", "lu", "lux"},
    "Canada": {"canada", "ca", "can"},
    "États-Unis": {"etats unis", "usa", "us", "united states", "united states of america"},
    "Royaume-Uni": {"royaume uni", "uk", "united kingdom", "gb", "great britain", "england"},
    "Allemagne": {"allemagne", "germany", "de", "deutschland"},
    "Espagne": {"espagne", "spain", "es", "espana"},
    "Italie": {"italie", "italy", "it", "italia"},
    "Portugal": {"portugal", "pt"},
    "Pays-Bas": {"pays bas", "netherlands", "nl", "holland"},
    "Irlande": {"irlande", "ireland", "ie"},
    "Maroc": {"maroc", "morocco", "ma"},
    "Tunisie": {"tunisie", "tunisia", "tn"},
    "Sénégal": {"senegal", "sn"},
    "Maurice": {"maurice", "mauritius", "ile maurice", "mu"},
    "La Réunion": {"la reunion", "reunion", "re"},
    "Côte d'Ivoire": {"cote d ivoire", "ivory coast", "ci"},
}

_ALIAS_TO_COUNTRY = {
    alias: country for country, aliases in COUNTRY_ALIASES.items() for alias in aliases
}

REMOTE_KEYWORDS = (
    "remote", "full remote", "fully remote", "100 remote", "teletravail", "teletravail total",
    "work from home", "anywhere", "a distance",
)  # fmt: skip
HYBRID_KEYWORDS = ("hybrid", "hybride", "teletravail partiel", "partial remote", "flex office")


def normalize_country(value: str | None) -> str | None:
    """Retourne le nom canonique d'un pays, ou la valeur nettoyée si le pays est inconnu."""
    if not value or not value.strip():
        return None
    return _ALIAS_TO_COUNTRY.get(normalize_text(value), value.strip())


def known_country(value: str | None) -> str | None:
    """Nom canonique si `value` est un pays connu, sinon None."""
    return _ALIAS_TO_COUNTRY.get(normalize_text(value)) if value else None


def detect_country(text: str | None) -> str | None:
    """Cherche un nom de pays (pas un code à 2 lettres, trop ambigu) dans un texte."""
    padded = f" {normalize_text(text)} "
    for alias, country in sorted(_ALIAS_TO_COUNTRY.items(), key=lambda item: -len(item[0])):
        if len(alias) > 3 and f" {alias} " in padded:
            return country
    return None


def contains_keyword(text: str | None, keywords: tuple[str, ...]) -> bool:
    padded = f" {normalize_text(text)} "
    return any(f" {keyword} " in padded for keyword in keywords)


def same_place(a: str | None, b: str | None) -> bool:
    """Compare deux villes ou deux pays sans tenir compte des accents / majuscules."""
    return bool(a and b and normalize_text(a) == normalize_text(b))
