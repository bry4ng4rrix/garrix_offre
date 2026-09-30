"""Logging structuré.

- LOG_FORMAT=json    : une ligne JSON par événement (production, facile à indexer).
- LOG_FORMAT=console : format lisible pour le développement.

Chaque module utilise un logger nommé, par exemple :

    logger = logging.getLogger("app.scraping")
    logger.info("Source fetched", extra={"source_id": str(source.id), "jobs": 12})

Le filtre `SensitiveDataFilter` masque automatiquement les mots de passe, tokens,
clés d'API, etc. avant l'écriture du log.
"""

import json
import logging
import re
import sys
from datetime import UTC, datetime
from typing import Any

from app.core.config import Settings

# Attributs standards d'un LogRecord : tout le reste vient de `extra=...`.
_STANDARD_ATTRIBUTES = set(logging.LogRecord("", 0, "", 0, "", (), None).__dict__.keys()) | {
    "message",
    "asctime",
    "taskName",
}

SENSITIVE_KEY_PATTERN = re.compile(
    r"pass(word)?|secret|token|authorization|api[_-]?key|cookie|credential", re.IGNORECASE
)
SENSITIVE_VALUE_PATTERNS = [
    (re.compile(r"(Bearer\s+)[A-Za-z0-9\-._~+/]+=*", re.IGNORECASE), r"\1***"),
    (re.compile(r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"), "***JWT***"),
    (re.compile(r"(/bot)\d+:[A-Za-z0-9_-]+"), r"\1***"),  # token Telegram dans une URL
    (re.compile(r"(://[^:/@\s]+:)[^@\s]+(@)"), r"\1***\2"),  # mot de passe dans une URL
    (
        re.compile(
            r"([?&](?:app_key|app_id|api_key|apikey|key|token|access_token)=)[^&\s]+", re.IGNORECASE
        ),
        r"\1***",
    ),
]
REDACTED = "***"


def redact_text(text: str) -> str:
    for pattern, replacement in SENSITIVE_VALUE_PATTERNS:
        text = pattern.sub(replacement, text)
    return text


def redact_value(key: str, value: Any) -> Any:
    if SENSITIVE_KEY_PATTERN.search(key):
        return REDACTED
    if isinstance(value, dict):
        return {k: redact_value(str(k), v) for k, v in value.items()}
    if isinstance(value, list | tuple):
        return [redact_value(key, item) for item in value]
    if isinstance(value, str):
        return redact_text(value)
    return value


class SensitiveDataFilter(logging.Filter):
    """Masque les données sensibles dans le message et dans les champs `extra`."""

    def filter(self, record: logging.LogRecord) -> bool:
        if isinstance(record.msg, str):
            record.msg = redact_text(record.msg)
        if record.args:
            if isinstance(record.args, dict):
                record.args = {k: redact_value(str(k), v) for k, v in record.args.items()}
            else:
                record.args = tuple(redact_value("", arg) for arg in record.args)
        for key, value in list(record.__dict__.items()):
            if key not in _STANDARD_ATTRIBUTES:
                setattr(record, key, redact_value(key, value))
        return True


def _extra_fields(record: logging.LogRecord) -> dict[str, Any]:
    return {k: v for k, v in record.__dict__.items() if k not in _STANDARD_ATTRIBUTES}


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        entry: dict[str, Any] = {
            "timestamp": datetime.fromtimestamp(record.created, tz=UTC).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        entry.update(_extra_fields(record))
        if record.exc_info:
            entry["exception"] = redact_text(self.formatException(record.exc_info))
        return json.dumps(entry, default=str, ensure_ascii=False)


class ConsoleFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        time = datetime.fromtimestamp(record.created, tz=UTC).strftime("%H:%M:%S")
        extras = " ".join(f"{k}={v}" for k, v in _extra_fields(record).items())
        line = f"{time} {record.levelname:<7} {record.name:<22} {record.getMessage()}"
        if extras:
            line = f"{line} | {extras}"
        if record.exc_info:
            line = f"{line}\n{redact_text(self.formatException(record.exc_info))}"
        return line


def setup_logging(settings: Settings) -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter() if settings.LOG_FORMAT == "json" else ConsoleFormatter())
    handler.addFilter(SensitiveDataFilter())

    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(settings.LOG_LEVEL.upper())

    # httpx écrit les URLs appelées en INFO : l'URL Telegram contient le token du bot.
    for noisy_logger in ("httpx", "httpcore", "multipart", "watchfiles"):
        logging.getLogger(noisy_logger).setLevel(logging.WARNING)
    # Les logs d'accès uvicorn sont remplacés par notre middleware (app.request).
    logging.getLogger("uvicorn.access").disabled = True
