from app.api.dependencies import DbSession
from app.modules.preferences.service import PreferencesService


def get_preferences_service(session: DbSession) -> PreferencesService:
    return PreferencesService(session)
