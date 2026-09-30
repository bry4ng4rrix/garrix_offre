"""Registre des adapters disponibles.

Un adapter s'enregistre avec le décorateur `@register_adapter` ; il est ensuite
utilisable par une source via son champ `adapter` (ex: "rss_feed").
"""

from app.modules.scraping.base import SourceAdapter

_ADAPTERS: dict[str, type[SourceAdapter]] = {}


def register_adapter[AdapterT: type[SourceAdapter]](adapter_class: AdapterT) -> AdapterT:
    if adapter_class.key in _ADAPTERS:
        raise ValueError(f"Adapter '{adapter_class.key}' is already registered")
    _ADAPTERS[adapter_class.key] = adapter_class
    return adapter_class


def get_adapter_class(key: str) -> type[SourceAdapter] | None:
    _load_builtin_adapters()
    return _ADAPTERS.get(key)


def list_adapters() -> list[type[SourceAdapter]]:
    _load_builtin_adapters()
    return sorted(_ADAPTERS.values(), key=lambda adapter: adapter.key)


def _load_builtin_adapters() -> None:
    """Importe les adapters fournis (l'import déclenche leur enregistrement)."""
    from app.modules.scraping.adapters import (  # noqa: F401
        example_api,
        example_html,
        example_rss,
        france_travail,
    )
