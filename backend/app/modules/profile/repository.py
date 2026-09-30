import uuid

from sqlalchemy import select

from app.modules.profile.models import Profile
from app.shared.repository import BaseRepository


class ProfileRepository(BaseRepository[Profile]):
    model = Profile

    def get_by_user(self, user_id: uuid.UUID) -> Profile | None:
        return self.session.scalar(select(Profile).where(Profile.user_id == user_id))

    def get_or_create(self, user_id: uuid.UUID, email: str | None = None) -> Profile:
        """Retourne le profil de l'utilisateur, en créant un profil vide si besoin."""
        profile = self.get_by_user(user_id)
        if profile is None:
            profile = self.add(Profile(user_id=user_id, email=email))
        return profile
