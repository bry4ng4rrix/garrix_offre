"""Validation Pydantic des entrées de l'API."""

import pytest
from pydantic import ValidationError

from app.modules.auth.schemas import RegisterRequest
from app.modules.experiences.schemas import ExperienceCreate
from app.modules.preferences.schemas import LocationPreference, PreferencesUpdate
from app.modules.profile.schemas import ProfileUpdate
from app.modules.recruiters.schemas import RecruiterCreate
from app.modules.scraping.schemas import JobPayload
from app.shared.enums import SkillRequirement


@pytest.mark.parametrize("password", ["short1", "onlyletters", "12345678"])
def test_weak_passwords_are_rejected(password: str) -> None:
    with pytest.raises(ValidationError):
        RegisterRequest(email="jane@example.com", password=password)


def test_email_is_validated() -> None:
    with pytest.raises(ValidationError):
        RegisterRequest(email="not-an-email", password="Passw0rd!")


def test_job_payload_accepts_simple_values() -> None:
    payload = JobPayload.model_validate(
        {
            "external_id": 42,
            "title": "  Python Developer  ",
            "company": "Exemple SAS",
            "location": "Paris, France",
            "contract": "CDI",
            "salary": "45k€",
            "skills": ["Python", {"name": "Docker", "requirement": "preferred"}],
            "application": "jobs@example.com",
            "unknown_field": "ignored",
        }
    )
    assert payload.external_id == "42"
    assert payload.title == "Python Developer"
    assert payload.company and payload.company.name == "Exemple SAS"
    assert payload.location and payload.location.raw == "Paris, France"
    assert payload.contract and payload.contract.type == "CDI"
    assert payload.salary and payload.salary.raw == "45k€"
    assert payload.skills[1].requirement == SkillRequirement.PREFERRED
    assert payload.application and payload.application.email == "jobs@example.com"


def test_job_payload_requires_a_title() -> None:
    with pytest.raises(ValidationError):
        JobPayload.model_validate({"url": "https://example.com"})


def test_recruiter_contact_needs_provenance() -> None:
    with pytest.raises(ValidationError, match="contact_source"):
        RecruiterCreate(name="Alex", email="alex@example.com")
    with pytest.raises(ValidationError, match="source_url"):
        RecruiterCreate(name="Alex", email="alex@example.com", contact_source="public_profile")
    ok = RecruiterCreate(name="Alex", email="alex@example.com", contact_source="job_listing")
    assert ok.email == "alex@example.com"


def test_preferences_languages_are_normalized() -> None:
    assert PreferencesUpdate(languages=["FR", "en", "fr"]).languages == ["en", "fr"]
    with pytest.raises(ValidationError):
        PreferencesUpdate(languages=["french!"])
    with pytest.raises(ValidationError):
        PreferencesUpdate(currency="euro")


def test_location_preference_needs_city_or_country() -> None:
    assert LocationPreference(country="fr").country == "France"
    with pytest.raises(ValidationError):
        LocationPreference()


def test_profile_validation() -> None:
    with pytest.raises(ValidationError):
        ProfileUpdate(phone="call me maybe")
    with pytest.raises(ValidationError):
        ProfileUpdate(linkedin_url="not a url")
    assert ProfileUpdate(country="MG").country == "Madagascar"


def test_experience_dates_are_consistent() -> None:
    with pytest.raises(ValidationError):
        ExperienceCreate(
            company_name="A", job_title="Dev", start_date="2024-01-01", end_date="2023-01-01"
        )
    with pytest.raises(ValidationError):
        ExperienceCreate(
            company_name="A",
            job_title="Dev",
            start_date="2024-01-01",
            end_date="2024-06-01",
            is_current=True,
        )
