"""Interface commune des fournisseurs d'IA.

Le reste du backend n'utilise JAMAIS un fournisseur directement : il passe par
`AIService` (service.py), qui appelle un `AIProvider`. Pour ajouter un fournisseur :
1. créer `providers/mon_fournisseur.py` avec une classe qui hérite de `AIProvider` ;
2. ajouter sa valeur dans AI_PROVIDER (core/config.py) ;
3. le retourner dans `get_ai_provider()` (providers/__init__ ou service.py).
"""

from abc import ABC, abstractmethod
from typing import Any, Literal

from app.core.exceptions import ExternalServiceError

Effort = Literal["low", "medium", "high"]


class AIProviderError(ExternalServiceError):
    """Le fournisseur d'IA a échoué (réseau, quota, refus...) : on bascule sur les règles."""

    code = "AI_PROVIDER_ERROR"
    message = "The AI provider failed"


class AIProvider(ABC):
    name: str
    model: str

    @abstractmethod
    def complete_text(self, system: str, prompt: str, effort: Effort = "medium") -> str:
        """Génère un texte libre (lettre de motivation, email...)."""

    @abstractmethod
    def complete_json(
        self, system: str, prompt: str, schema: dict[str, Any], effort: Effort = "low"
    ) -> dict[str, Any]:
        """Génère une réponse JSON conforme à `schema` (JSON Schema)."""
