import contextlib
from collections.abc import Iterator
from typing import Any

from fastapi import UploadFile
from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError
from app.modules.documents.models import Document
from app.modules.documents.service import DocumentService
from app.modules.experiences.service import ExperienceLevelService
from app.modules.preferences.repository import SearchPreferenceRepository
from app.modules.profile.models import Profile
from app.modules.profile.repository import ProfileRepository
from app.modules.profile.schemas import ProfileUpdate
from app.modules.users.models import User
from app.shared.enums import DocumentType

# Champs gérés par la table search_preferences (source unique de vérité).
PREFERENCE_FIELDS = {"minimum_salary", "currency", "salary_period", "remote"}
URL_FIELDS = {"linkedin_url", "github_url", "portfolio_url"}
COMPLETION_FIELDS = (
    "first_name", "last_name", "professional_title", "email", "phone", "city", "country",
    "bio", "availability", "years_of_experience", "experience_level", "languages",
    "photo_document_id",
)  # fmt: skip


class ProfileService:
    """Profil professionnel : identité, localisation, disponibilité, langues et photo.

    Le salaire minimum, la devise et le télétravail sont lus/écrits dans les préférences
    de recherche : c'est la même donnée que dans GET/PUT /preferences.
    """

    def __init__(self, session: Session) -> None:
        self.session = session
        self.profiles = ProfileRepository(session)
        self.preferences = SearchPreferenceRepository(session)
        self.documents = DocumentService(session)

    def get_profile(self, user: User) -> dict[str, Any]:
        profile = self.profiles.get_or_create(user.id, user.email)
        self.preferences.get_or_create(user.id)
        self.session.commit()
        return self._to_view(user, profile)

    def update_profile(self, user: User, data: ProfileUpdate) -> dict[str, Any]:
        profile = self.profiles.get_or_create(user.id, user.email)
        preference = self.preferences.get_or_create(user.id)
        updates = data.model_dump(exclude_unset=True, mode="json")

        if updates.get("experience_level"):
            level_code = updates["experience_level"].strip().lower()
            ExperienceLevelService(self.session).ensure_codes_exist([level_code])
            updates["experience_level"] = level_code

        for field, value in updates.items():
            if field in PREFERENCE_FIELDS:
                if value is not None or field == "minimum_salary":
                    setattr(preference, field, value)
            elif field == "available_from":
                profile.available_from = data.available_from
            else:
                setattr(profile, field, value)
        self.session.commit()
        return self._to_view(user, profile)

    # --- Photo ---

    def upload_photo(self, user: User, file: UploadFile) -> dict[str, Any]:
        profile = self.profiles.get_or_create(user.id, user.email)
        previous_photo_id = profile.photo_document_id
        photo = self.documents.upload(
            user, file, DocumentType.PHOTO, title="Photo de profil", is_primary=True
        )
        profile.photo_document_id = photo.id
        self.session.commit()
        if previous_photo_id:
            self._delete_document_quietly(user, previous_photo_id)
        return self._to_view(user, profile)

    def delete_photo(self, user: User) -> None:
        profile = self.profiles.get_by_user(user.id)
        if profile is None or profile.photo_document_id is None:
            raise NotFoundError("No profile photo", code="PHOTO_NOT_FOUND")
        photo_id = profile.photo_document_id
        profile.photo_document_id = None
        self.session.commit()
        self._delete_document_quietly(user, photo_id)

    def stream_photo(self, user: User) -> tuple[Document, Iterator[bytes]]:
        profile = self.profiles.get_by_user(user.id)
        if profile is None or profile.photo_document_id is None:
            raise NotFoundError("No profile photo", code="PHOTO_NOT_FOUND")
        return self.documents.stream(user, profile.photo_document_id)

    # --- Interne ---

    def _delete_document_quietly(self, user: User, document_id: Any) -> None:
        with contextlib.suppress(NotFoundError):
            self.documents.delete(user, document_id)

    def _to_view(self, user: User, profile: Profile) -> dict[str, Any]:
        preference = self.preferences.get_or_create(user.id)
        filled = sum(1 for field in COMPLETION_FIELDS if getattr(profile, field))
        return {
            "id": profile.id,
            "first_name": profile.first_name,
            "last_name": profile.last_name,
            "full_name": profile.full_name,
            "professional_title": profile.professional_title,
            "email": profile.email,
            "phone": profile.phone,
            "country": profile.country,
            "city": profile.city,
            "professional_address": profile.professional_address,
            "bio": profile.bio,
            "availability": profile.availability,
            "available_from": profile.available_from,
            "years_of_experience": profile.years_of_experience,
            "experience_level": profile.experience_level,
            "mobility": profile.mobility,
            "languages": profile.languages,
            "linkedin_url": profile.linkedin_url,
            "github_url": profile.github_url,
            "portfolio_url": profile.portfolio_url,
            "minimum_salary": preference.minimum_salary,
            "currency": preference.currency,
            "salary_period": preference.salary_period,
            "remote": preference.remote,
            "photo_url": "/api/v1/profile/photo" if profile.photo_document_id else None,
            "completion_percent": round(100 * filled / len(COMPLETION_FIELDS)),
            "updated_at": profile.updated_at,
        }
