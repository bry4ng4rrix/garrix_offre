import pytest

from app.modules.scraping.normalizer import clean_email, clean_url, compute_fingerprint
from app.modules.scraping.schemas import NormalizedJob
from app.modules.scraping.text_parsing import (
    detect_languages,
    detect_work_time,
    find_salary_in_text,
    language_code,
    parse_location,
    parse_min_years,
    parse_salary,
)
from app.modules.scraping.validator import JobValidator
from app.shared.utils import canonical_url, normalize_company_name, normalize_text


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("35k - 45k € / an", (35000, 45000, "EUR", "year")),
        ("45 000 € - 55 000 € brut annuel", (45000, 55000, "EUR", "year")),
        ("$120,000 - $150,000 a year", (120000, 150000, "USD", "year")),
        ("500€/jour", (500, 500, "EUR", "day")),
        ("TJM 450 €", (450, 450, "EUR", "day")),
        ("3000 € brut mensuel", (3000, 3000, "EUR", "month")),
        ("1 500 000 Ar par mois", (1500000, 1500000, "MGA", "month")),
        ("40 - 50 k€", (40000, 50000, "EUR", "year")),
    ],
)
def test_parse_salary(text: str, expected: tuple[int, int, str, str]) -> None:
    info = parse_salary(text)
    assert (info.minimum, info.maximum, info.currency, info.period) == expected


def test_parse_salary_without_numbers() -> None:
    assert parse_salary("Salaire attractif").minimum is None


def test_find_salary_ignores_unrelated_numbers() -> None:
    text = "3+ ans d'expérience. Salaire : 45 - 55 k€ par an. Démarrage en 2026."
    info = find_salary_in_text(text)
    assert (info.minimum, info.maximum) == (45000, 55000)


@pytest.mark.parametrize(
    ("raw", "city", "country", "remote", "hybrid"),
    [
        ("Paris, France", "Paris", "France", False, False),
        ("Remote", None, None, True, False),
        ("Antananarivo, Madagascar", "Antananarivo", "Madagascar", False, False),
        ("Lyon (69)", "Lyon", None, False, False),
        ("Hybride - Nantes", "Nantes", None, False, True),
        ("Remote - France", None, "France", True, False),
        ("USA Only", None, "États-Unis", False, False),
    ],
)
def test_parse_location(
    raw: str, city: str | None, country: str | None, remote: bool, hybrid: bool
) -> None:
    info = parse_location(raw)
    assert (info.city, info.country, info.remote, info.hybrid) == (city, country, remote, hybrid)


@pytest.mark.parametrize(
    ("text", "years"),
    [
        ("3+ years of experience with Python", 3),
        ("Minimum 5 ans d'expérience", 5),
        ("Notre société a 10 ans", None),
        (None, None),
    ],
)
def test_parse_min_years(text: str | None, years: int | None) -> None:
    assert parse_min_years(text) == years


def test_work_time_and_languages() -> None:
    assert detect_work_time("Poste à temps partiel") == "part_time"
    assert detect_work_time("Full-time position") == "full_time"
    assert language_code("Français") == "fr"
    assert language_code("English") == "en"
    french = (
        "Nous recherchons un développeur pour notre équipe et vous travaillerez avec les équipes."
    )
    assert detect_languages(french) == ["fr"]
    assert "en" in detect_languages(french + " Anglais courant.")


def test_normalize_text_and_company_names() -> None:
    assert normalize_text("Développeur Full-Stack (H/F)") == "developpeur full stack"
    assert normalize_company_name("Exemple SAS") == normalize_company_name("exemple")
    assert normalize_text("C++ / C#") == "c++ c#"


def test_canonical_url_removes_tracking() -> None:
    assert (
        canonical_url("HTTPS://Example.com/jobs/1/?utm_source=x&b=2&a=1#top")
        == "https://example.com/jobs/1?a=1&b=2"
    )
    assert canonical_url("javascript:alert(1)") is None
    assert clean_url("ftp://example.com/file") is None


def test_clean_email_never_invents() -> None:
    assert clean_email("mailto:Jobs@Example.com") == "jobs@example.com"
    assert clean_email("not an email") is None


def test_fingerprint_is_stable_across_sources() -> None:
    a = compute_fingerprint("Développeur Python (H/F)", "Exemple SAS", "Paris", False)
    b = compute_fingerprint("developpeur python", "EXEMPLE", "paris", False)
    c = compute_fingerprint("Développeur Python", "Exemple SAS", "Lyon", False)
    assert a == b
    assert a != c


def _normalized(**overrides: object) -> NormalizedJob:
    values: dict[str, object] = {
        "external_id": "1", "title": "Python Developer", "normalized_title": "python developer",
        "description": "x" * 80, "source_url": "https://example.com/1", "company_name": "Exemple",
        "company": {}, "recruiter": None, "location_raw": "Paris", "city": "Paris", "country": None,
        "is_remote": False, "is_hybrid": False, "contract_type": None, "work_time": None,
        "salary_min": None, "salary_max": None, "salary_currency": None, "salary_period": None,
        "salary_raw": None, "experience_level": None, "min_years_experience": None, "skills": [],
        "languages": [], "application_url": None, "application_email": None, "published_at": None,
        "expires_at": None, "fingerprint": "f",
    }  # fmt: skip
    values.update(overrides)
    return NormalizedJob(**values)  # type: ignore[arg-type]


def test_validator_rejects_invalid_and_flags_incomplete() -> None:
    validator = JobValidator()
    assert validator.validate(_normalized()).is_complete
    invalid = validator.validate(
        _normalized(normalized_title="x", source_url=None, external_id=None)
    )
    assert set(invalid.errors) == {"invalid_title", "missing_identifier"}
    incomplete = validator.validate(_normalized(description=None, company_name=None))
    assert incomplete.is_valid and not incomplete.is_complete
    assert set(incomplete.quality_issues) == {"missing_description", "missing_company"}
