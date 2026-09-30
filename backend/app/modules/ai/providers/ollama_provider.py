"""Fournisseur Ollama : modèle open source exécuté sur votre propre serveur (aucune donnée
envoyée à un service externe).

Configuration : AI_PROVIDER=ollama, OLLAMA_BASE_URL (ex. http://host.docker.internal:11434),
AI_MODEL (vide = qwen3:4b), AI_TIMEOUT_SECONDS (300 conseillé sans GPU).

Choix techniques :
- API `/api/chat` sans streaming ;
- réponses JSON : sortie structurée d'Ollama (`format` = JSON Schema) ;
- `think: false` : pas de phase de réflexion (plus rapide sur processeur) ; si un modèle
  renvoie malgré tout un bloc <think>...</think>, il est retiré ;
- toute erreur (serveur injoignable, délai dépassé, réponse tronquée ou vide) lève
  AIProviderError : AIService bascule alors sur les modèles de texte déterministes.
"""

import json
import logging
import re
from typing import Any

import httpx

from app.modules.ai.base import AIProvider, AIProviderError, Effort

logger = logging.getLogger("app.ai")

DEFAULT_MODEL = "qwen3:4b"

# Fenêtre de contexte : consignes + profil + offre (description limitée à 6000 caractères)
# tiennent largement ; la valeur par défaut d'Ollama (4096) couperait le début des consignes.
NUM_CTX = 8192

# Température et longueur maximale de la réponse selon le type de tâche.
_OPTIONS: dict[Effort, dict[str, Any]] = {
    "low": {"temperature": 0.2, "num_predict": 700, "num_ctx": NUM_CTX},
    "medium": {"temperature": 0.5, "num_predict": 1200, "num_ctx": NUM_CTX},
    "high": {"temperature": 0.6, "num_predict": 2400, "num_ctx": NUM_CTX},
}
_THINK_BLOCK = re.compile(r"<think>.*?</think>", re.DOTALL)


class OllamaProvider(AIProvider):
    name = "ollama"

    def __init__(
        self,
        base_url: str,
        model: str | None = None,
        timeout: float = 300.0,
        transport: httpx.BaseTransport | None = None,
    ) -> None:
        self.model = model or DEFAULT_MODEL
        # `transport` permet aux tests de simuler le serveur Ollama.
        self.client = httpx.Client(
            base_url=base_url.rstrip("/"), timeout=timeout, transport=transport
        )

    def complete_text(self, system: str, prompt: str, effort: Effort = "medium") -> str:
        return self._call(system, prompt, effort)

    def complete_json(
        self, system: str, prompt: str, schema: dict[str, Any], effort: Effort = "low"
    ) -> dict[str, Any]:
        text = self._call(system, prompt, effort, schema)
        try:
            data = json.loads(text)
        except json.JSONDecodeError as exc:
            raise AIProviderError(
                "The AI returned invalid JSON", code="AI_INVALID_RESPONSE"
            ) from exc
        if not isinstance(data, dict):
            raise AIProviderError(
                "The AI returned an unexpected JSON value", code="AI_INVALID_RESPONSE"
            )
        return data

    def _call(
        self, system: str, prompt: str, effort: Effort, schema: dict[str, Any] | None = None
    ) -> str:
        payload: dict[str, Any] = {
            "model": self.model,
            "stream": False,
            "think": False,
            "keep_alive": "15m",
            "options": _OPTIONS[effort],
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": prompt},
            ],
        }
        if schema is not None:
            payload["format"] = schema
        try:
            response = self.client.post("/api/chat", json=payload)
        except httpx.TimeoutException as exc:
            raise AIProviderError("The AI took too long to answer", code="AI_UNREACHABLE") from exc
        except httpx.HTTPError as exc:
            raise AIProviderError("The AI server is unreachable", code="AI_UNREACHABLE") from exc
        if response.status_code >= 400:
            logger.error(
                "AI provider error",
                extra={"status_code": response.status_code, "body": response.text[:200]},
            )
            raise AIProviderError("The AI provider returned an error")

        body = response.json()
        if body.get("done_reason") == "length":
            raise AIProviderError("The AI response was truncated", code="AI_TRUNCATED")
        content = (body.get("message") or {}).get("content") or ""
        text = _THINK_BLOCK.sub("", content).strip()
        if not text:
            raise AIProviderError("The AI returned an empty response", code="AI_EMPTY_RESPONSE")
        logger.info(
            "AI call done",
            extra={
                "model": body.get("model", self.model),
                "input_tokens": body.get("prompt_eval_count"),
                "output_tokens": body.get("eval_count"),
                "duration_s": round((body.get("total_duration") or 0) / 1e9, 1),
            },
        )
        return text
