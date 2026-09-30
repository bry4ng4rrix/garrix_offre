from typing import Any

from sqlalchemy.orm import Session

from app.modules.contract_types.service import ContractTypeService
from app.modules.experiences.service import ExperienceLevelService, ExperiencePreferenceService
from app.modules.job_titles.service import JobTitleService
from app.modules.preferences.models import SearchPreference
from app.modules.preferences.repository import SearchPreferenceRepository
from app.modules.preferences.schemas import PreferencesUpdate
from app.modules.users.models import User


class PreferencesService:
    """Vue centrale des préférences de recherche (GET/PUT /api/v1/preferences).

    Agrège des données de plusieurs modules :
    - search_preferences (localisation, remote, salaire, langues, seuil de matching) ;
    - job_titles (postes recherchés) ;
    - contract_types (types de contrat sélectionnés) ;
    - experience_preferences (technologies recherchées).
    """

    def __init__(self, session: Session) -> None:
        self.session = session
        self.repository = SearchPreferenceRepository(session)
        self.job_titles = JobTitleService(session)
        self.technologies = ExperiencePreferenceService(session)
        self.contract_types = ContractTypeService(session)
        self.levels = ExperienceLevelService(session)

    def get_or_create(self, user: User) -> SearchPreference:
        return self.repository.get_or_create(user.id)

    def get_preferences(self, user: User) -> dict[str, Any]:
        preference = self.get_or_create(user)
        self.session.commit()
        return self._to_view(user, preference)

    def update_preferences(self, user: User, data: PreferencesUpdate) -> dict[str, Any]:
        preference = self.get_or_create(user)
        updates = data.model_dump(exclude_unset=True)

        if "job_titles" in updates and updates["job_titles"] is not None:
            self.job_titles.sync_titles(user, updates.pop("job_titles"))
        if "skills" in updates and updates["skills"] is not None:
            self.technologies.sync_technologies(user, updates.pop("skills"))
        if "contract_types" in updates and updates["contract_types"] is not None:
            preference.contract_types = self.contract_types.resolve_codes(
                updates.pop("contract_types")
            )
        if "experience_levels" in updates and updates["experience_levels"] is not None:
            preference.experience_levels = self.levels.ensure_codes_exist(
                updates.pop("experience_levels")
            )
        if "locations" in updates and updates["locations"] is not None:
            preference.locations = [location.model_dump() for location in data.locations or []]
            updates.pop("locations")

        for field, value in updates.items():
            if value is not None:
                setattr(preference, field, value)
            elif field == "minimum_salary":
                preference.minimum_salary = None  # null explicite = pas de minimum
        self.session.commit()
        return self._to_view(user, preference)

    def _to_view(self, user: User, preference: SearchPreference) -> dict[str, Any]:
        return {
            "job_titles": [
                item.title for item in self.job_titles.list_titles(user, enabled_only=True)
            ],
            "contract_types": preference.contract_type_codes,
            "skills": [
                item.technology
                for item in self.technologies.list_preferences(user, enabled_only=True)
            ],
            "experience_levels": preference.experience_levels,
            "locations": preference.locations,
            "remote": preference.remote,
            "hybrid": preference.hybrid,
            "onsite": preference.onsite,
            "minimum_salary": preference.minimum_salary,
            "currency": preference.currency,
            "salary_period": preference.salary_period,
            "languages": preference.languages,
            "matching_threshold": preference.matching_threshold,
        }
