"""AIService : analyse et génération de texte, indépendamment du fournisseur.

    analyze_job()                  -> résumé, compétences, exigences d'une offre
    extract_skills()               -> compétences obligatoires / appréciées
    extract_requirements()         -> exigences (années, diplôme, langues...)
    generate_application()         -> lettre de motivation, email, réponse au recruteur, résumé
    analyze_recruiter_response()   -> type de réponse (entretien, refus...) et statut suggéré

Si l'IA n'est pas configurée (AI_PROVIDER=none) ou échoue, chaque méthode utilise les
règles déterministes de rules.py : l'IA est un complément, jamais une dépendance.
"""

import logging
from collections.abc import Callable
from functools import lru_cache
from typing import Any, TypeVar

from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.modules.ai import prompts, rules
from app.modules.ai.base import AIProvider, AIProviderError
from app.modules.ai.schemas import GeneratedBy, GenerationKind
from app.modules.jobs.models import Job
from app.modules.skills.extraction import SkillExtractor
from app.modules.skills.repository import SkillRepository

logger = logging.getLogger("app.ai")

T = TypeVar("T")


@lru_cache
def get_ai_provider() -> AIProvider | None:
    """Fournisseur configuré dans le .env, ou None (mode sans IA)."""
    settings = get_settings()
    if settings.AI_PROVIDER == "anthropic":
        if settings.AI_API_KEY is None:
            logger.warning("AI_PROVIDER=anthropic but AI_API_KEY is empty: AI disabled")
            return None
        from app.modules.ai.providers.anthropic_provider import AnthropicProvider

        return AnthropicProvider(
            settings.AI_API_KEY.get_secret_value(), settings.AI_MODEL, settings.AI_TIMEOUT_SECONDS
        )
    if settings.AI_PROVIDER == "ollama":
        from app.modules.ai.providers.ollama_provider import OllamaProvider

        return OllamaProvider(
            settings.OLLAMA_BASE_URL, settings.AI_MODEL, settings.AI_TIMEOUT_SECONDS
        )
    return None


class AIService:
    """Point d'entrée unique vers l'IA pour tout le backend."""

    def __init__(self, session: Session, provider: AIProvider | None = None) -> None:
        # `provider` permet aux tests d'injecter un faux fournisseur.
        self.session = session
        self.provider = provider or get_ai_provider()
        self._extractor: SkillExtractor | None = None

    @property
    def enabled(self) -> bool:
        return self.provider is not None

    def status(self) -> dict[str, Any]:
        return {
            "enabled": self.enabled,
            "provider": self.provider.name if self.provider else "none",
            "model": self.provider.model if self.provider else None,
        }

    # --- Analyse ---

    def analyze_job(self, job: Job) -> dict[str, Any]:
        company = job.company.name if job.company else None

        def with_ai(provider: AIProvider) -> dict[str, Any]:
            prompt = "Analyse cette offre.\n" + prompts.job_block(
                job.title, company, job.description
            )
            return provider.complete_json(
                prompts.JOB_ANALYST_SYSTEM, prompt, prompts.JOB_ANALYSIS_SCHEMA, effort="low"
            )

        analysis, source = self._run(
            with_ai,
            lambda: rules.analyze_job(
                self.extractor, job.title, job.description, job.experience_level
            ),
        )
        analysis["requirements"] = self.extract_requirements(job.title, job.description)
        return {**analysis, "generated_by": source}

    def extract_skills(self, title: str, description: str | None) -> dict[str, Any]:
        def with_ai(provider: AIProvider) -> dict[str, Any]:
            prompt = "Liste les compétences techniques demandées.\n" + prompts.job_block(
                title, None, description
            )
            return provider.complete_json(
                prompts.JOB_ANALYST_SYSTEM, prompt, prompts.SKILLS_SCHEMA, effort="low"
            )

        result, source = self._run(
            with_ai, lambda: rules.extract_skills(self.extractor, title, description)
        )
        return {**result, "generated_by": source}

    def extract_requirements(self, title: str, description: str | None) -> dict[str, Any]:
        def with_ai(provider: AIProvider) -> dict[str, Any]:
            prompt = "Liste les exigences du poste.\n" + prompts.job_block(title, None, description)
            return provider.complete_json(
                prompts.JOB_ANALYST_SYSTEM, prompt, prompts.REQUIREMENTS_SCHEMA, effort="low"
            )

        result, source = self._run(with_ai, lambda: rules.extract_requirements(description))
        return {**result, "generated_by": source}

    def analyze_recruiter_response(self, subject: str | None, body: str | None) -> dict[str, Any]:
        def with_ai(provider: AIProvider) -> dict[str, Any]:
            prompt = (
                f"Classe cette réponse.\n<email>\nObjet : {subject or ''}\n\n{body or ''}\n</email>"
            )
            return provider.complete_json(
                prompts.RESPONSE_ANALYST_SYSTEM,
                prompt,
                prompts.RESPONSE_ANALYSIS_SCHEMA,
                effort="low",
            )

        result, source = self._run(with_ai, lambda: rules.classify_response(subject, body))
        return {**result, "generated_by": source}

    # --- Génération ---

    def generate_application(
        self,
        kind: GenerationKind,
        candidate: dict[str, Any],
        job_title: str,
        company: str | None,
        description: str | None,
        context: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Génère un brouillon. Rien n'est envoyé : l'utilisateur relit et valide (RG-10)."""
        context = context or {}
        job = prompts.job_block(job_title, company, description)
        person = prompts.candidate_block(candidate)

        def with_ai(provider: AIProvider) -> dict[str, Any]:
            match kind:
                case GenerationKind.APPLICATION_EMAIL:
                    prompt = f"Rédige l'email de candidature (le CV est en pièce jointe).\n{person}\n{job}"
                    data = provider.complete_json(
                        prompts.WRITER_SYSTEM, prompt, prompts.EMAIL_SCHEMA, effort="medium"
                    )
                    return {"subject": data["subject"], "content": data["body"]}
                case GenerationKind.JOB_SUMMARY:
                    prompt = f"Résume cette offre en 5 lignes maximum.\n{job}"
                    return {
                        "subject": None,
                        "content": provider.complete_text(
                            prompts.JOB_ANALYST_SYSTEM, prompt, "low"
                        ),
                    }
                case GenerationKind.RECRUITER_REPLY:
                    email = f"<email>\n{context.get('recruiter_message', '')}\n</email>"
                    prompt = f"Rédige une réponse courte à ce recruteur.\n{person}\n{job}\n{email}"
                    return {
                        "subject": None,
                        "content": provider.complete_text(prompts.WRITER_SYSTEM, prompt, "medium"),
                    }
                case _:
                    prompt = f"Rédige une lettre de motivation (250 à 350 mots).\n{person}\n{job}"
                    return {
                        "subject": None,
                        "content": provider.complete_text(prompts.WRITER_SYSTEM, prompt, "medium"),
                    }

        def with_rules() -> dict[str, Any]:
            match kind:
                case GenerationKind.APPLICATION_EMAIL:
                    email = rules.application_email(candidate, job_title, company)
                    return {"subject": email["subject"], "content": email["body"]}
                case GenerationKind.JOB_SUMMARY:
                    return {
                        "subject": None,
                        "content": rules.summarize(description, max_sentences=4),
                    }
                case GenerationKind.RECRUITER_REPLY:
                    reply = rules.recruiter_reply(context.get("response_type", "other"), candidate)
                    return {"subject": None, "content": reply}
                case _:
                    return {
                        "subject": None,
                        "content": rules.cover_letter(candidate, job_title, company),
                    }

        result, source = self._run(with_ai, with_rules)
        return {"kind": kind, **result, "generated_by": source}

    # --- Interne ---

    @property
    def extractor(self) -> SkillExtractor:
        if self._extractor is None:
            self._extractor = SkillExtractor(SkillRepository(self.session).list_all_skills())
        return self._extractor

    def _run(
        self, with_ai: Callable[[AIProvider], T], with_rules: Callable[[], T]
    ) -> tuple[T, GeneratedBy]:
        if self.provider is not None:
            try:
                return with_ai(self.provider), GeneratedBy.AI
            except AIProviderError as exc:
                logger.warning("AI unavailable, using rules: %s", exc.code)
            except (KeyError, TypeError) as exc:
                logger.warning("Unexpected AI response, using rules: %s", type(exc).__name__)
        return with_rules(), GeneratedBy.RULES
