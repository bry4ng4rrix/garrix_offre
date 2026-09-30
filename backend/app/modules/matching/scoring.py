"""Calcul du score de correspondance entre UNE offre et UN profil.

Ce fichier ne contient que des fonctions pures : pas de base de données, pas de réseau.
On peut donc le tester facilement (tests/unit/test_scoring.py).

Principe (UML 15) :
1. chaque critère donne un sous-score entre 0 et 1 (ou None s'il ne s'applique pas,
   par exemple aucun salaire minimum renseigné) ;
2. le score final = moyenne pondérée des sous-scores applicables, ramenée sur 100 ;
3. chaque critère ajoute des "raisons" lisibles pour expliquer le score.
"""

from dataclasses import dataclass, field
from difflib import SequenceMatcher

from app.modules.matching import rules
from app.shared.enums import Priority, SkillLevel, SkillRequirement
from app.shared.geo import same_place
from app.shared.utils import normalize_text

# ---------------------------------------------------------------------------
# Données d'entrée
# ---------------------------------------------------------------------------


@dataclass
class CandidateSkill:
    name: str
    level: SkillLevel = SkillLevel.INTERMEDIATE


@dataclass
class TechnologyPreference:
    name: str
    priority: Priority = Priority.MEDIUM
    is_required: bool = False


@dataclass
class LocationWish:
    city: str | None = None
    country: str | None = None


@dataclass
class CandidateProfile:
    """Tout ce que le matching doit savoir du candidat."""

    skills: list[CandidateSkill] = field(default_factory=list)
    technologies: list[TechnologyPreference] = field(default_factory=list)
    job_titles: list[str] = field(default_factory=list)
    contract_types: list[str] = field(default_factory=list)
    experience_levels: list[str] = field(default_factory=list)
    experience_level: str | None = None
    years_of_experience: int | None = None
    locations: list[LocationWish] = field(default_factory=list)
    city: str | None = None
    country: str | None = None
    accepts_remote: bool = True
    accepts_hybrid: bool = True
    accepts_onsite: bool = True
    minimum_salary: int | None = None
    salary_currency: str = "EUR"
    salary_period: str = "month"
    languages: list[str] = field(default_factory=list)


@dataclass
class JobCriteria:
    """Tout ce que le matching doit savoir de l'offre."""

    title: str
    skills: list[tuple[str, SkillRequirement]] = field(default_factory=list)
    contract_type: str | None = None
    experience_level: str | None = None
    min_years_experience: int | None = None
    city: str | None = None
    country: str | None = None
    is_remote: bool = False
    is_hybrid: bool = False
    salary_min: int | None = None
    salary_max: int | None = None
    salary_currency: str | None = None
    salary_period: str | None = None
    languages: list[str] = field(default_factory=list)


@dataclass
class MatchingWeights:
    skills: int = 40
    experience: int = 20
    contract: int = 15
    location: int = 10
    salary: int = 10
    language: int = 5
    title: int = 10
    experience_level: int = 10


# ---------------------------------------------------------------------------
# Résultat
# ---------------------------------------------------------------------------


@dataclass
class CriterionResult:
    """Sous-score d'un critère. score=None : critère non applicable (ignoré)."""

    score: float | None
    matched: bool | None
    reasons: list[str] = field(default_factory=list)


@dataclass
class MatchResult:
    score: int
    matched_skills: list[str]
    missing_skills: list[str]
    experience_match: bool | None
    location_match: bool | None
    contract_match: bool | None
    salary_match: bool | None
    language_match: bool | None
    title_match: bool | None
    experience_level_match: bool | None
    reasons: list[str]
    breakdown: dict[str, dict[str, float | int | None]]


# ---------------------------------------------------------------------------
# Critères
# ---------------------------------------------------------------------------


def score_skills(
    profile: CandidateProfile, job: JobCriteria
) -> tuple[CriterionResult, list[str], list[str]]:
    """Compétences de l'offre possédées par le candidat (les obligatoires comptent double)."""
    if not profile.skills:
        return (
            CriterionResult(None, None, ["Ajoutez vos compétences pour affiner le score"]),
            [],
            [],
        )
    if not job.skills:
        return (
            CriterionResult(rules.UNKNOWN_SCORE, None, ["Aucune compétence détectée dans l'offre"]),
            [],
            [],
        )

    candidate = {normalize_text(skill.name): skill for skill in profile.skills}
    total = earned = 0.0
    matched: list[str] = []
    missing: list[str] = []
    for name, requirement in job.skills:
        weight = rules.REQUIREMENT_WEIGHTS[requirement]
        total += weight
        skill = candidate.get(normalize_text(name))
        if skill:
            earned += weight * rules.SKILL_LEVEL_FACTORS[skill.level]
            matched.append(name)
        else:
            missing.append(name)

    score = earned / total
    reasons = [f"Compétences correspondantes : {len(matched)}/{len(job.skills)}"]
    required_missing = [
        name for name, req in job.skills if req == SkillRequirement.REQUIRED and name in missing
    ]
    if required_missing:
        reasons.append("Compétences obligatoires manquantes : " + ", ".join(required_missing[:5]))
    return CriterionResult(score, score >= rules.MATCH_THRESHOLD, reasons), matched, missing


def score_experience(profile: CandidateProfile, job: JobCriteria) -> tuple[CriterionResult, bool]:
    """Technologies / expériences recherchées présentes dans l'offre.

    Retourne aussi `required_missing` : une technologie obligatoire est absente.
    """
    if not profile.technologies:
        return CriterionResult(None, None), False
    job_skills = {normalize_text(name) for name, _ in job.skills}
    job_skills.update(normalize_text(job.title).split())

    total = earned = 0.0
    found: list[str] = []
    required_missing: list[str] = []
    for technology in profile.technologies:
        weight = rules.PRIORITY_WEIGHTS[technology.priority]
        total += weight
        if normalize_text(technology.name) in job_skills:
            earned += weight
            found.append(technology.name)
        elif technology.is_required:
            required_missing.append(technology.name)

    score = earned / total
    reasons = []
    if found:
        reasons.append("Technologies recherchées présentes : " + ", ".join(found[:6]))
    if required_missing:
        reasons.append("Technologies obligatoires absentes : " + ", ".join(required_missing))
    matched = not required_missing and score >= rules.MATCH_THRESHOLD
    return CriterionResult(score, matched, reasons), bool(required_missing)


def score_title(profile: CandidateProfile, job: JobCriteria) -> CriterionResult:
    """Proximité entre le titre de l'offre et les postes recherchés."""
    if not profile.job_titles:
        return CriterionResult(None, None)
    job_words = _title_words(job.title)
    best_score, best_title = 0.0, ""
    for wanted in profile.job_titles:
        wanted_words = _title_words(wanted)
        if not wanted_words:
            continue
        overlap = len(job_words & wanted_words) / len(wanted_words)
        similarity = SequenceMatcher(
            None, " ".join(sorted(job_words)), " ".join(sorted(wanted_words))
        ).ratio()
        candidate_score = max(overlap, similarity * 0.9)
        if candidate_score > best_score:
            best_score, best_title = candidate_score, wanted
    matched = best_score >= rules.MATCH_THRESHOLD
    reasons = (
        [f"Titre proche de « {best_title} »"]
        if matched
        else ["Titre éloigné des postes recherchés"]
    )
    return CriterionResult(best_score, matched, reasons)


def score_contract(profile: CandidateProfile, job: JobCriteria) -> CriterionResult:
    if not profile.contract_types:
        return CriterionResult(None, None)
    if not job.contract_type:
        return CriterionResult(rules.UNKNOWN_SCORE, None, ["Type de contrat non précisé"])
    if job.contract_type in profile.contract_types:
        return CriterionResult(1.0, True, [f"Contrat recherché ({job.contract_type})"])
    return CriterionResult(0.0, False, [f"Contrat non recherché ({job.contract_type})"])


def score_location(profile: CandidateProfile, job: JobCriteria) -> CriterionResult:
    """Localisation et mode de travail (sur site, hybride, télétravail)."""
    if job.is_remote:
        if profile.accepts_remote:
            return CriterionResult(1.0, True, ["Télétravail complet"])
        return CriterionResult(rules.UNKNOWN_SCORE, None, ["Poste en télétravail (non recherché)"])

    place_score, place_reason = _place_score(profile, job)
    wanted_mode = profile.accepts_hybrid if job.is_hybrid else profile.accepts_onsite
    mode_label = "hybride" if job.is_hybrid else "sur site"
    if place_score is None:
        return CriterionResult(None, None)
    score = place_score if wanted_mode else place_score * rules.UNWANTED_WORK_MODE_FACTOR
    reasons = [place_reason] if place_reason else []
    if not wanted_mode:
        reasons.append(f"Mode de travail {mode_label} non recherché")
    return CriterionResult(score, score >= rules.MATCH_THRESHOLD, reasons)


def score_salary(profile: CandidateProfile, job: JobCriteria) -> CriterionResult:
    if not profile.minimum_salary:
        return CriterionResult(None, None)
    offered = job.salary_max or job.salary_min
    if not offered or not job.salary_period:
        return CriterionResult(rules.UNKNOWN_SCORE, None, ["Salaire non précisé"])
    if job.salary_currency and job.salary_currency != profile.salary_currency:
        return CriterionResult(
            rules.UNKNOWN_SCORE, None, [f"Salaire dans une autre devise ({job.salary_currency})"]
        )

    offered_year = offered * rules.SALARY_PERIOD_TO_YEAR.get(job.salary_period, 1)
    wanted_year = profile.minimum_salary * rules.SALARY_PERIOD_TO_YEAR.get(profile.salary_period, 1)
    if offered_year >= wanted_year:
        return CriterionResult(1.0, True, ["Salaire conforme à votre minimum"])
    ratio = offered_year / wanted_year
    score = max(0.0, (ratio - 0.5) * 2)  # 50 % du minimum ou moins -> 0
    return CriterionResult(
        score, False, [f"Salaire inférieur à votre minimum ({round(ratio * 100)} %)"]
    )


def score_languages(profile: CandidateProfile, job: JobCriteria) -> CriterionResult:
    if not profile.languages:
        return CriterionResult(None, None)
    if not job.languages:
        return CriterionResult(rules.UNKNOWN_SCORE, None)
    spoken = {code.lower() for code in profile.languages}
    required = {code.lower() for code in job.languages}
    missing = sorted(required - spoken)
    score = 1 - len(missing) / len(required)
    if missing:
        return CriterionResult(score, False, ["Langue(s) non maîtrisée(s) : " + ", ".join(missing)])
    return CriterionResult(score, True, ["Langues de l'offre maîtrisées"])


def score_experience_level(
    profile: CandidateProfile, job: JobCriteria, level_ranks: dict[str, int]
) -> CriterionResult:
    """Niveau (junior, senior...) et années d'expérience demandées."""
    parts: list[float] = []
    reasons: list[str] = []

    job_rank = level_ranks.get(job.experience_level or "")
    if job.experience_level and job.experience_level in profile.experience_levels:
        parts.append(1.0)
        reasons.append(f"Niveau recherché ({job.experience_level})")
    if not parts and job_rank is not None:
        profile_rank = level_ranks.get(profile.experience_level or "")
        if profile_rank is not None:
            gap = profile_rank - job_rank
            if gap in rules.LEVEL_GAP_SCORES:
                parts.append(rules.LEVEL_GAP_SCORES[gap])
            elif gap > 0:
                parts.append(rules.LEVEL_OVERQUALIFIED_SCORE)
                reasons.append("Poste moins senior que votre profil")
            else:
                parts.append(rules.LEVEL_UNDERQUALIFIED_SCORE)
                reasons.append("Poste plus senior que votre profil")

    if job.min_years_experience and profile.years_of_experience is not None:
        if profile.years_of_experience >= job.min_years_experience:
            parts.append(1.0)
        else:
            parts.append(profile.years_of_experience / job.min_years_experience)
            reasons.append(f"{job.min_years_experience} ans d'expérience demandés")

    if not parts:
        if profile.experience_level is None and profile.years_of_experience is None:
            return CriterionResult(None, None)
        return CriterionResult(rules.UNKNOWN_SCORE, None)
    score = sum(parts) / len(parts)
    return CriterionResult(score, score >= rules.MATCH_THRESHOLD, reasons)


# ---------------------------------------------------------------------------
# Score final
# ---------------------------------------------------------------------------


def compute_match(
    profile: CandidateProfile,
    job: JobCriteria,
    weights: MatchingWeights,
    level_ranks: dict[str, int] | None = None,
) -> MatchResult:
    """Calcule le score (0-100) et les raisons, à partir des critères pondérés."""
    skills, matched_skills, missing_skills = score_skills(profile, job)
    experience, required_missing = score_experience(profile, job)
    criteria: dict[str, tuple[CriterionResult, int]] = {
        "skills": (skills, weights.skills),
        "experience": (experience, weights.experience),
        "title": (score_title(profile, job), weights.title),
        "contract": (score_contract(profile, job), weights.contract),
        "location": (score_location(profile, job), weights.location),
        "salary": (score_salary(profile, job), weights.salary),
        "language": (score_languages(profile, job), weights.language),
        "experience_level": (
            score_experience_level(profile, job, level_ranks or {}),
            weights.experience_level,
        ),
    }

    weighted_sum = total_weight = 0.0
    breakdown: dict[str, dict[str, float | int | None]] = {}
    reasons: list[str] = []
    for name, (result, weight) in criteria.items():
        breakdown[name] = {
            "score": round(result.score, 3) if result.score is not None else None,
            "weight": weight,
        }
        reasons.extend(result.reasons)
        if result.score is None or weight <= 0:
            continue
        weighted_sum += result.score * weight
        total_weight += weight

    score = round(100 * weighted_sum / total_weight) if total_weight else 0
    if total_weight == 0:
        reasons.append("Profil incomplet : renseignez compétences et préférences")
    if required_missing and score > rules.REQUIRED_TECHNOLOGY_MISSING_MAX_SCORE:
        score = rules.REQUIRED_TECHNOLOGY_MISSING_MAX_SCORE
        reasons.append(f"Score plafonné à {score} : technologie obligatoire absente")

    return MatchResult(
        score=max(0, min(100, score)),
        matched_skills=matched_skills,
        missing_skills=missing_skills,
        experience_match=criteria["experience"][0].matched,
        location_match=criteria["location"][0].matched,
        contract_match=criteria["contract"][0].matched,
        salary_match=criteria["salary"][0].matched,
        language_match=criteria["language"][0].matched,
        title_match=criteria["title"][0].matched,
        experience_level_match=criteria["experience_level"][0].matched,
        reasons=reasons,
        breakdown=breakdown,
    )


# ---------------------------------------------------------------------------
# Outils internes
# ---------------------------------------------------------------------------


def _title_words(title: str) -> set[str]:
    text = f" {normalize_text(title)} "
    for source, target in rules.TITLE_SYNONYMS.items():
        text = text.replace(f" {source} ", f" {target} ")
    return {word for word in text.split() if word not in rules.TITLE_STOPWORDS}


def _place_score(profile: CandidateProfile, job: JobCriteria) -> tuple[float | None, str | None]:
    """Compare le lieu de l'offre aux lieux souhaités (ou, à défaut, au lieu du profil)."""
    wishes = profile.locations or (
        [LocationWish(profile.city, profile.country)] if (profile.city or profile.country) else []
    )
    if not wishes:
        return None, None
    if not (job.city or job.country):
        return rules.UNKNOWN_SCORE, "Lieu non précisé"
    for wish in wishes:
        if wish.city and same_place(wish.city, job.city):
            return 1.0, f"Lieu recherché ({job.city})"
    for wish in wishes:
        if not wish.city and same_place(wish.country, job.country):
            return 1.0, f"Pays recherché ({job.country})"
    for wish in wishes:
        if same_place(wish.country, job.country):
            return rules.SAME_COUNTRY_SCORE, f"Même pays ({job.country}), autre ville"
    return 0.0, "Lieu hors de vos préférences"
