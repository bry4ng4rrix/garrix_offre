"""Étape NORMALIZE du pipeline : JobPayload (format collecté) -> NormalizedJob (format commun).

La normalisation :
- nettoie les textes et les URLs ;
- reconnaît le type de contrat, le niveau, le lieu, le télétravail, le salaire ;
- détecte les compétences du catalogue dans le titre et la description ;
- calcule une empreinte (fingerprint) utilisée par la déduplication.

Elle ne déduit JAMAIS de coordonnées (email, téléphone) : elle recopie seulement
celles présentes dans l'offre (RG-07).
"""

import hashlib
import re
from datetime import UTC, datetime
from typing import Any

from sqlalchemy.orm import Session

from app.modules.contract_types.repository import ContractTypeRepository
from app.modules.contract_types.service import match_contract_type
from app.modules.experiences.repository import ExperienceLevelRepository
from app.modules.experiences.service import level_for_years, match_experience_level
from app.modules.scraping import text_parsing
from app.modules.scraping.schemas import JobPayload, NormalizedJob, NormalizedSkill
from app.modules.skills.extraction import SkillExtractor
from app.modules.skills.repository import SkillRepository
from app.shared.enums import ContactSource
from app.shared.geo import HYBRID_KEYWORDS, REMOTE_KEYWORDS, contains_keyword, normalize_country
from app.shared.utils import canonical_url, normalize_company_name, normalize_text

_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[a-z]{2,}$", re.IGNORECASE)
_PHONE = re.compile(r"^\+?[0-9 ().-]{6,30}$")
_WHITESPACE = re.compile(r"[ \t]+")
# Termes trop fréquents dans une description pour en déduire un type de contrat.
AMBIGUOUS_CONTRACT_CODES = {"contract", "full_time", "part_time"}


def clean_email(value: str | None) -> str | None:
    value = (value or "").strip().lower().removeprefix("mailto:")
    return value if _EMAIL.match(value) else None


def clean_phone(value: str | None) -> str | None:
    value = (value or "").strip()
    return value if _PHONE.match(value) else None


def clean_url(value: str | None) -> str | None:
    return canonical_url(value)


def clean_text(value: str | None) -> str | None:
    if not value:
        return None
    lines = [_WHITESPACE.sub(" ", line).strip() for line in value.replace("\r", "").split("\n")]
    text = re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip()
    return text or None


def compute_fingerprint(
    title: str, company_name: str | None, city: str | None, remote: bool
) -> str:
    """Empreinte d'une offre : même titre + même entreprise + même lieu = même offre."""
    place = normalize_text(city) or ("remote" if remote else "")
    key = f"{normalize_text(title)}|{normalize_company_name(company_name)}|{place}"
    return hashlib.sha256(key.encode("utf-8")).hexdigest()


class NormalizerService:
    """Transforme une offre collectée en offre au format commun de l'application."""

    def __init__(self, session: Session) -> None:
        # Référentiels chargés une seule fois pour tout un lot d'offres.
        self.contract_types = ContractTypeRepository(session).list_types(include_inactive=True)
        self.description_contract_types = [
            item for item in self.contract_types if item.code not in AMBIGUOUS_CONTRACT_CODES
        ]
        self.levels = ExperienceLevelRepository(session).list_levels()
        self.skill_extractor = SkillExtractor(SkillRepository(session).list_all_skills())

    def normalize(self, payload: JobPayload) -> NormalizedJob:
        title = clean_text(payload.title) or payload.title
        description = clean_text(payload.description)
        full_text = f"{title}\n{description or ''}"

        location = self._location(payload, title, description)
        salary = self._salary(payload, description)
        contract_text = payload.contract.type if payload.contract else None
        contract_type = (
            match_contract_type(contract_text, self.contract_types)
            or match_contract_type(title, self.contract_types)
            or match_contract_type(description, self.description_contract_types)
        )
        work_time_text = payload.contract.work_time if payload.contract else None
        work_time = text_parsing.detect_work_time(
            work_time_text or contract_text
        ) or text_parsing.detect_work_time(description)

        min_years = payload.min_years_experience or text_parsing.parse_min_years(description)
        experience_level = (
            match_experience_level(payload.experience_level, self.levels)
            or match_experience_level(title, self.levels)
            or level_for_years(min_years, self.levels)
        )

        company = self._company(payload)
        url = clean_url(payload.url)
        return NormalizedJob(
            external_id=payload.external_id,
            title=title[:500],
            normalized_title=normalize_text(title)[:500],
            description=description,
            source_url=url,
            company_name=company.get("name"),
            company=company,
            recruiter=self._recruiter(payload, url),
            location_raw=(payload.location.raw if payload.location else None),
            city=location.city,
            country=location.country,
            is_remote=location.remote,
            is_hybrid=location.hybrid and not location.remote,
            contract_type=contract_type,
            work_time=work_time,
            salary_min=salary.minimum,
            salary_max=salary.maximum,
            salary_currency=salary.currency,
            salary_period=salary.period,
            salary_raw=payload.salary.raw if payload.salary else None,
            experience_level=experience_level,
            min_years_experience=min_years,
            skills=self._skills(payload, title, description),
            languages=self._languages(payload, full_text),
            application_url=clean_url(payload.application.url if payload.application else None)
            or url,
            application_email=clean_email(
                payload.application.email if payload.application else None
            ),
            published_at=_as_utc(payload.published_at),
            expires_at=_as_utc(payload.expires_at),
            fingerprint=compute_fingerprint(
                title, company.get("name"), location.city, location.remote
            ),
            raw_data=payload.raw_data or payload.model_dump(mode="json", exclude={"raw_data"}),
        )

    # --- Étapes de détail ---

    @staticmethod
    def _location(
        payload: JobPayload, title: str, description: str | None
    ) -> text_parsing.LocationInfo:
        given = payload.location
        parsed = text_parsing.parse_location(given.raw if given else None)
        city = (given.city if given and given.city else None) or parsed.city
        country = normalize_country(given.country) if given and given.country else parsed.country
        remote = given.remote if given and given.remote is not None else parsed.remote
        hybrid = given.hybrid if given and given.hybrid is not None else parsed.hybrid
        if not remote and contains_keyword(title, REMOTE_KEYWORDS):
            remote = True
        if not (remote or hybrid) and contains_keyword(description, HYBRID_KEYWORDS):
            hybrid = True
        return text_parsing.LocationInfo(
            city=city, country=country, remote=bool(remote), hybrid=bool(hybrid)
        )

    @staticmethod
    def _salary(payload: JobPayload, description: str | None) -> text_parsing.SalaryInfo:
        given = payload.salary
        parsed = text_parsing.parse_salary(given.raw if given else None)
        if not parsed.minimum and not (given and (given.min or given.max)):
            parsed = text_parsing.find_salary_in_text(description)
        minimum = int(given.min) if given and given.min else parsed.minimum
        maximum = int(given.max) if given and given.max else parsed.maximum or minimum
        if minimum and maximum and minimum > maximum:
            minimum, maximum = maximum, minimum
        currency = (given.currency if given and given.currency else parsed.currency) or None
        currency = (
            text_parsing.CURRENCIES.get(currency.lower(), currency.upper()) if currency else None
        )
        period = (given.period if given and given.period else None) or parsed.period
        if period and period not in text_parsing.PERIODS:
            period = text_parsing.parse_salary(f"1 {period}").period
        return text_parsing.SalaryInfo(minimum, maximum, currency[:3] if currency else None, period)

    def _skills(
        self, payload: JobPayload, title: str, description: str | None
    ) -> list[NormalizedSkill]:
        skills: dict[str, NormalizedSkill] = {}
        for item in payload.skills:
            if normalize_text(item.name):
                skills.setdefault(
                    normalize_text(item.name),
                    NormalizedSkill(name=item.name, requirement=item.requirement),
                )
        for name, requirement in self.skill_extractor.extract(title, description):
            skills.setdefault(
                normalize_text(name), NormalizedSkill(name=name, requirement=requirement)
            )
        return list(skills.values())

    @staticmethod
    def _languages(payload: JobPayload, text: str) -> list[str]:
        codes = {code for value in payload.languages if (code := text_parsing.language_code(value))}
        codes.update(text_parsing.detect_languages(text))
        return sorted(codes)

    @staticmethod
    def _company(payload: JobPayload) -> dict[str, Any]:
        company = payload.company
        if company is None or not company.name:
            return {}
        return {
            "name": clean_text(company.name),
            "website": clean_url(company.website),
            "logo_url": clean_url(company.logo_url),
            "description": clean_text(company.description),
            "industry": company.industry,
            "employee_count": company.employee_count,
            "address": company.address,
            "postal_code": company.postal_code,
            "city": company.city,
            "country": normalize_country(company.country),
            "email": clean_email(company.email),
            "phone": clean_phone(company.phone),
            "linkedin_url": clean_url(company.linkedin_url),
            "facebook_url": clean_url(company.facebook_url),
            "instagram_url": clean_url(company.instagram_url),
        }

    @staticmethod
    def _recruiter(payload: JobPayload, job_url: str | None) -> dict[str, Any] | None:
        recruiter = payload.recruiter
        if recruiter is None:
            return None
        data = {
            "name": clean_text(recruiter.name),
            "first_name": recruiter.first_name,
            "last_name": recruiter.last_name,
            "job_title": recruiter.job_title,
            "email": clean_email(recruiter.email),
            "phone": clean_phone(recruiter.phone),
            "linkedin_url": clean_url(recruiter.linkedin_url),
            "website": clean_url(recruiter.website),
        }
        if not any(data.values()):
            return None
        data["contact_source"] = (recruiter.contact_source or ContactSource.JOB_LISTING).value
        data["source_url"] = clean_url(recruiter.source_url) or job_url
        return data


def _as_utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)
