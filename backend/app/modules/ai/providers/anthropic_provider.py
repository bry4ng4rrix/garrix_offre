"""Fournisseur Claude (Anthropic), via le SDK officiel `anthropic`.

Configuration : AI_PROVIDER=anthropic, AI_API_KEY=<clé>, AI_MODEL (vide = claude-opus-5-5).

Choix techniques :
- `output_config.effort` est fixé explicitement : "low" pour l'extraction et la
  classification, "medium" pour la rédaction ;
- les réponses JSON utilisent les sorties structurées (`output_config.format`) : le texte
  renvoyé est garanti conforme au schéma ;
- `fallbacks="default"` : si un filtre de sécurité refuse une requête légitime, l'API la
  rejoue automatiquement sur le modèle de repli recommandé ;
- un refus (`stop_reason == "refusal"`) ou une réponse tronquée lève AIProviderError,
  et AIService bascule alors sur les règles déterministes.
"""

import json
import logging
from typing import Any

import anthropic

from app.modules.ai.base import AIProvider, AIProviderError, Effort

logger = logging.getLogger("app.ai")

DEFAULT_MODEL = "claude-opus-5-5"
FALLBACK_BETA = "server-side-fallback-2026-07-01"
MAX_TOKENS = 16000  # la réflexion du modèle compte aussi dans ce plafond


class AnthropicProvider(AIProvider):
    name = "anthropic"

    def __init__(self, api_key: str, model: str | None = None, timeout: float = 120.0) -> None:
        self.model = model or DEFAULT_MODEL
        self.client = anthropic.Anthropic(api_key=api_key, timeout=timeout, max_retries=2)

    def complete_text(self, system: str, prompt: str, effort: Effort = "medium") -> str:
        return self._call(system, prompt, {"effort": effort})

    def complete_json(
        self, system: str, prompt: str, schema: dict[str, Any], effort: Effort = "low"
    ) -> dict[str, Any]:
        output_config: dict[str, Any] = {
            "effort": effort,
            "format": {"type": "json_schema", "schema": schema},
        }
        text = self._call(system, prompt, output_config)
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

    def _call(self, system: str, prompt: str, output_config: dict[str, Any]) -> str:
        try:
            response = self.client.beta.messages.create(
                model=self.model,
                max_tokens=MAX_TOKENS,
                system=system,
                messages=[{"role": "user", "content": prompt}],
                output_config=output_config,  # type: ignore[arg-type]
                betas=[FALLBACK_BETA],
                fallbacks="default",
            )
        except anthropic.RateLimitError as exc:
            raise AIProviderError("AI rate limit reached", code="AI_RATE_LIMITED") from exc
        except anthropic.APIStatusError as exc:
            logger.error("AI provider error", extra={"status_code": exc.status_code})
            raise AIProviderError("The AI provider returned an error") from exc
        except anthropic.APIConnectionError as exc:
            raise AIProviderError("The AI provider is unreachable", code="AI_UNREACHABLE") from exc

        if response.stop_reason == "refusal":
            category = response.stop_details.category if response.stop_details else None
            logger.warning("AI request declined", extra={"category": category})
            raise AIProviderError("The AI declined this request", code="AI_REFUSED")
        if response.stop_reason == "max_tokens":
            raise AIProviderError("The AI response was truncated", code="AI_TRUNCATED")

        # La réponse peut commencer par des blocs "thinking" : on lit uniquement les blocs texte.
        text = "".join(block.text for block in response.content if block.type == "text").strip()
        if not text:
            raise AIProviderError("The AI returned an empty response", code="AI_EMPTY_RESPONSE")
        logger.info(
            "AI call done",
            extra={
                "model": response.model,
                "input_tokens": response.usage.input_tokens,
                "output_tokens": response.usage.output_tokens,
            },
        )
        return text
