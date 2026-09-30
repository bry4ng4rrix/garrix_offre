import uuid

from sqlalchemy import select

from app.modules.preferences.models import SearchPreference
from app.shared.repository import BaseRepository


class SearchPreferenceRepository(BaseRepository[SearchPreference]):
    model = SearchPreference

    def get_by_user(self, user_id: uuid.UUID) -> SearchPreference | None:
        return self.session.scalar(
            select(SearchPreference).where(SearchPreference.user_id == user_id)
        )

    def get_or_create(self, user_id: uuid.UUID) -> SearchPreference:
        preference = self.get_by_user(user_id)
        if preference is None:
            preference = self.add(SearchPreference(user_id=user_id))
        return preference
