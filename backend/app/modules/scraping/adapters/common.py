"""Petits outils partagés par les adapters."""

import os
import re
from functools import lru_cache
from pathlib import Path
from typing import Any

from bs4 import BeautifulSoup
from dotenv import dotenv_values

from app.modules.scraping.http import ScrapingError

# Les secrets des sources (clés d'API) sont des variables d'environnement préfixées SOURCE_.
# Le préfixe empêche une configuration de source de lire un autre secret (JWT, SMTP...).
SECRET_NAME = re.compile(r"^SOURCE_[A-Z0-9_]+$")
_PLACEHOLDER = re.compile(r"\{(SOURCE_[A-Z0-9_]+)\}")


def html_to_text(html: str | None) -> str | None:
    """Convertit une description HTML en texte lisible (paragraphes conservés)."""
    if not html:
        return None
    soup = BeautifulSoup(html, "html.parser")
    for tag in soup(["script", "style"]):
        tag.decompose()
    text = soup.get_text("\n")
    lines = [line.strip() for line in text.splitlines()]
    cleaned = "\n".join(line for line in lines if line)
    return cleaned or None


def get_path(data: Any, path: str | None) -> Any:
    """Lit une valeur par chemin pointé : get_path(item, "company.name")."""
    if not path:
        return None
    current = data
    for part in path.split("."):
        if isinstance(current, dict):
            current = current.get(part)
        elif isinstance(current, list) and part.isdigit() and int(part) < len(current):
            current = current[int(part)]
        else:
            return None
    return current


def secret_names(template: str) -> list[str]:
    """Noms des variables utilisées : "SOURCE_KEY" ou "Token {SOURCE_KEY}"."""
    if SECRET_NAME.match(template):
        return [template]
    names = _PLACEHOLDER.findall(template)
    if not names:
        raise ValueError(f"'{template}' must be SOURCE_NAME or contain {{SOURCE_NAME}}")
    return names


@lru_cache
def _dotenv() -> dict[str, str | None]:
    return dotenv_values(Path.cwd() / ".env")


def resolve_secret(template: str) -> str:
    """Remplace les noms de variables par leurs valeurs (environnement, puis fichier .env)."""
    values = {}
    for name in secret_names(template):
        value = os.environ.get(name) or _dotenv().get(name)
        if not value:
            raise ScrapingError(f"Missing environment variable {name}")
        values[name] = value
    if SECRET_NAME.match(template):
        return values[template]
    return _PLACEHOLDER.sub(lambda match: values[match.group(1)], template)
