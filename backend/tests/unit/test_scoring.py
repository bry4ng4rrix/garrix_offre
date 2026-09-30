"""Tests du calcul de score (modules/matching/scoring.py) : fonctions pures, sans base."""

from app.modules.matching import rules
from app.modules.matching.scoring import (
    CandidateProfile,
    CandidateSkill,
    JobCriteria,
    LocationWish,
    MatchingWeights,
    TechnologyPreference,
    compute_match,
    score_contract,
    score_experience_level,
    score_languages,
    score_location,
    score_salary,
    score_skills,
    score_title,
)
from app.shared.enums import Priority, SkillLevel, SkillRequirement

LEVEL_RANKS = {"junior": 1, "mid": 2, "senior": 3, "lead": 4}
REQUIRED = SkillRequirement.REQUIRED
PREFERRED = SkillRequirement.PREFERRED


def make_profile(**overrides: object) -> CandidateProfile:
    values: dict[str, object] = {
        "skills": [
            CandidateSkill("Python", SkillLevel.ADVANCED),
            CandidateSkill("React", SkillLevel.ADVANCED),
        ],
        "job_titles": ["Full Stack Developer"],
        "contract_types": ["cdi"],
        "experience_level": "mid",
        "years_of_experience": 4,
        "locations": [LocationWish("Paris", "France")],
        "minimum_salary": 40000,
        "salary_currency": "EUR",
        "salary_period": "year",
        "languages": ["fr", "en"],
    }
    values.update(overrides)
    return CandidateProfile(**values)  # type: ignore[arg-type]


def make_job(**overrides: object) -> JobCriteria:
    values: dict[str, object] = {
        "title": "Développeur Full Stack",
        "skills": [("Python", REQUIRED), ("React", REQUIRED)],
        "contract_type": "cdi",
        "experience_level": "mid",
        "city": "Paris",
        "country": "France",
        "salary_min": 45000,
        "salary_max": 55000,
        "salary_currency": "EUR",
        "salary_period": "year",
        "languages": ["fr"],
    }
    values.update(overrides)
    return JobCriteria(**values)  # type: ignore[arg-type]


def test_perfect_match_scores_100() -> None:
    result = compute_match(make_profile(), make_job(), MatchingWeights(), LEVEL_RANKS)
    assert result.score == 100
    assert result.matched_skills == ["Python", "React"]
    assert result.missing_skills == []
    assert result.contract_match and result.location_match and result.salary_match


def test_score_is_always_between_0_and_100() -> None:
    bad_job = make_job(
        title="Chef de cuisine", skills=[("Java", REQUIRED)], contract_type="stage",
        city="Lyon", country="Canada", salary_max=10000, languages=["de"], experience_level="lead",
    )  # fmt: skip
    result = compute_match(make_profile(), bad_job, MatchingWeights(), LEVEL_RANKS)
    assert 0 <= result.score <= 30
    assert result.missing_skills == ["Java"]


def test_required_skills_count_double() -> None:
    profile = make_profile(skills=[CandidateSkill("Python", SkillLevel.ADVANCED)])
    only_required_missing = make_job(skills=[("Python", PREFERRED), ("Go", REQUIRED)])
    only_preferred_missing = make_job(skills=[("Python", REQUIRED), ("Go", PREFERRED)])
    low, _, _ = score_skills(profile, only_required_missing)
    high, _, _ = score_skills(profile, only_preferred_missing)
    assert low.score is not None and high.score is not None
    assert low.score < high.score


def test_skill_level_reduces_credit() -> None:
    beginner = make_profile(skills=[CandidateSkill("Python", SkillLevel.BEGINNER)])
    expert = make_profile(skills=[CandidateSkill("Python", SkillLevel.EXPERT)])
    job = make_job(skills=[("Python", REQUIRED)])
    assert score_skills(beginner, job)[0].score == rules.SKILL_LEVEL_FACTORS[SkillLevel.BEGINNER]
    assert score_skills(expert, job)[0].score == 1.0


def test_skill_names_are_compared_without_case_or_accents() -> None:
    profile = make_profile(skills=[CandidateSkill("postgresql")])
    _, matched, _ = score_skills(profile, make_job(skills=[("PostgreSQL", REQUIRED)]))
    assert matched == ["PostgreSQL"]


def test_job_without_skills_gets_neutral_score() -> None:
    result, _, _ = score_skills(make_profile(), make_job(skills=[]))
    assert result.score == rules.UNKNOWN_SCORE
    assert result.matched is None


def test_criterion_without_preference_is_ignored() -> None:
    """Sans type de contrat souhaité, le contrat ne pèse pas dans le score."""
    profile = make_profile(contract_types=[])
    assert score_contract(profile, make_job(contract_type="stage")).score is None
    with_other_contract = compute_match(
        profile, make_job(contract_type="stage"), MatchingWeights(), LEVEL_RANKS
    )
    assert with_other_contract.score == 100


def test_weights_are_configurable() -> None:
    job = make_job(contract_type="freelance")  # seul critère non satisfait
    heavy_contract = compute_match(make_profile(), job, MatchingWeights(contract=100), LEVEL_RANKS)
    no_contract = compute_match(make_profile(), job, MatchingWeights(contract=0), LEVEL_RANKS)
    assert no_contract.score == 100
    assert heavy_contract.score < 60


def test_all_weights_zero_gives_zero_and_a_reason() -> None:
    weights = MatchingWeights(0, 0, 0, 0, 0, 0, 0, 0)
    result = compute_match(make_profile(), make_job(), weights, LEVEL_RANKS)
    assert result.score == 0
    assert any("incomplet" in reason for reason in result.reasons)


def test_remote_job_matches_when_remote_accepted() -> None:
    job = make_job(city=None, country=None, is_remote=True)
    assert score_location(make_profile(accepts_remote=True), job).score == 1.0
    refused = score_location(make_profile(accepts_remote=False), job)
    assert refused.score == rules.UNKNOWN_SCORE


def test_location_same_country_other_city() -> None:
    result = score_location(make_profile(), make_job(city="Lyon"))
    assert result.score == rules.SAME_COUNTRY_SCORE


def test_location_uses_profile_city_when_no_wish() -> None:
    profile = make_profile(locations=[], city="Antananarivo", country="Madagascar")
    assert score_location(profile, make_job(city="Antananarivo", country="Madagascar")).score == 1.0


def test_onsite_job_when_only_remote_wanted_is_penalized() -> None:
    profile = make_profile(accepts_onsite=False)
    result = score_location(profile, make_job())
    assert result.score == rules.UNWANTED_WORK_MODE_FACTOR


def test_salary_is_compared_on_a_yearly_basis() -> None:
    monthly_profile = make_profile(minimum_salary=3000, salary_period="month")
    daily_job = make_job(salary_min=None, salary_max=200, salary_period="day")  # 200 * 218 > 36 000
    assert score_salary(monthly_profile, daily_job).score == 1.0


def test_salary_below_minimum_is_proportional() -> None:
    result = score_salary(make_profile(minimum_salary=50000), make_job(salary_max=37500))
    assert result.matched is False
    assert result.score == 0.5  # 75 % du minimum


def test_salary_in_other_currency_is_unknown() -> None:
    result = score_salary(make_profile(), make_job(salary_currency="USD"))
    assert result.score == rules.UNKNOWN_SCORE


def test_languages() -> None:
    assert (
        score_languages(make_profile(languages=["fr"]), make_job(languages=["fr", "en"])).score
        == 0.5
    )
    assert score_languages(make_profile(languages=[]), make_job()).score is None


def test_experience_level_gap() -> None:
    profile = make_profile(experience_level="junior", years_of_experience=1)
    senior_job = make_job(experience_level="senior", min_years_experience=5)
    result = score_experience_level(profile, senior_job, LEVEL_RANKS)
    assert result.score is not None and result.score < 0.3
    assert result.matched is False


def test_targeted_experience_levels_take_priority() -> None:
    profile = make_profile(experience_levels=["senior"], experience_level="mid")
    assert (
        score_experience_level(profile, make_job(experience_level="senior"), LEVEL_RANKS).score
        == 1.0
    )


def test_title_similarity_handles_french_and_synonyms() -> None:
    profile = make_profile(job_titles=["Full Stack Developer"])
    assert score_title(profile, make_job(title="Développeur Fullstack (H/F)")).matched is True
    assert score_title(profile, make_job(title="Comptable")).matched is False


def test_missing_required_technology_caps_the_score() -> None:
    profile = make_profile(
        technologies=[TechnologyPreference("Kubernetes", Priority.HIGH, is_required=True)]
    )
    result = compute_match(profile, make_job(), MatchingWeights(), LEVEL_RANKS)
    assert result.score == rules.REQUIRED_TECHNOLOGY_MISSING_MAX_SCORE
    assert result.experience_match is False


def test_technology_preferences_found_in_job() -> None:
    profile = make_profile(
        technologies=[TechnologyPreference("React", Priority.HIGH, is_required=True)]
    )
    result = compute_match(profile, make_job(), MatchingWeights(), LEVEL_RANKS)
    assert result.experience_match is True
    assert result.score == 100


def test_breakdown_contains_every_criterion() -> None:
    result = compute_match(make_profile(), make_job(), MatchingWeights(), LEVEL_RANKS)
    assert set(result.breakdown) == {
        "skills", "experience", "title", "contract", "location", "salary", "language", "experience_level",
    }  # fmt: skip
    assert result.reasons
