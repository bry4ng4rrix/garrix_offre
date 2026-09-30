"""Détection des compétences du catalogue dans le texte d'une offre.

Exemple : avec "Python", "Django" et "React" (alias "reactjs") dans le catalogue,
"Développeur Python/Django, ReactJS apprécié" donne :
    [("Python", required), ("Django", required), ("React", preferred)]

Une compétence est "preferred" si toutes ses mentions sont dans une phrase contenant
un marqueur comme "apprécié", "un plus", "nice to have"...
"""

import re

from app.modules.skills.models import Skill
from app.shared.enums import SkillRequirement
from app.shared.utils import strip_accents

PREFERRED_MARKERS = (
    "nice to have", "un plus", "apprecie", "souhaite", "bonus", "preferred", "idealement",
    "is a plus", "optionnel", "optional", "serait un atout", "un atout",
)  # fmt: skip

_SENTENCE_SPLIT = re.compile(r"(?<=[.!?;\n])\s+|\n+")


def _pattern(term: str) -> re.Pattern[str] | None:
    term = term.strip()
    if len(term) < 2:
        return None  # "C" ou "R" seuls : trop ambigus dans un texte libre
    # Frontières adaptées à "C++", "C#", ".NET", "Node.js" (les \b classiques ne marchent pas).
    regex = rf"(?<![\w+#.]){re.escape(term)}(?![\w+#])"
    flags = 0 if len(term) <= 2 else re.IGNORECASE  # "Go" : sensible à la casse
    return re.compile(regex, flags)


class SkillExtractor:
    """Reconnaît les compétences du catalogue (noms + alias) dans un texte."""

    def __init__(self, skills: list[Skill]) -> None:
        self._patterns: list[tuple[str, list[re.Pattern[str]]]] = []
        for skill in skills:
            terms = {skill.name, *skill.aliases}
            patterns = [pattern for term in terms if (pattern := _pattern(term))]
            if patterns:
                self._patterns.append((skill.name, patterns))

    def extract(self, title: str, description: str | None) -> list[tuple[str, SkillRequirement]]:
        sentences = [title, *_SENTENCE_SPLIT.split(description or "")]
        found: list[tuple[str, SkillRequirement]] = []
        for name, patterns in self._patterns:
            mentions = [
                sentence for sentence in sentences if any(p.search(sentence) for p in patterns)
            ]
            if not mentions:
                continue
            only_optional = all(
                any(marker in strip_accents(sentence.lower()) for marker in PREFERRED_MARKERS)
                for sentence in mentions
            )
            found.append(
                (name, SkillRequirement.PREFERRED if only_optional else SkillRequirement.REQUIRED)
            )
        return found
