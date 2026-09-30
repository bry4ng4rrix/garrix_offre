"""Importe tous les modèles SQLAlchemy.

Nécessaire pour :
- Alembic (autogenerate compare la base à `Base.metadata`) ;
- les relations entre modules (SQLAlchemy doit connaître toutes les classes).

Quand vous créez un nouveau `models.py`, ajoutez son import ici.
"""

from app.modules.applications.models import (
    Application,
    ApplicationStatusHistory,
    RecruiterResponse,
)
from app.modules.audit.models import AuditLog
from app.modules.auth.models import RefreshToken
from app.modules.companies.models import Company
from app.modules.contract_types.models import ContractType
from app.modules.documents.models import Document
from app.modules.experiences.models import Experience, ExperienceLevel, ExperiencePreference
from app.modules.integrations.n8n.models import N8nWebhookEvent
from app.modules.job_titles.models import JobTitle
from app.modules.jobs.models import Job, JobSkill, JobSource, JobUserState
from app.modules.matching.models import JobMatch, MatchingSettings
from app.modules.notifications.models import Notification, NotificationSettings
from app.modules.preferences.models import SearchPreference, preference_contract_types
from app.modules.profile.models import Profile
from app.modules.recruiters.models import Recruiter
from app.modules.scraping.models import ScrapingRun
from app.modules.skills.models import ProfileSkill, Skill, SkillCategory
from app.modules.sources.models import Source
from app.modules.users.models import User

__all__ = [
    "Application",
    "ApplicationStatusHistory",
    "AuditLog",
    "Company",
    "ContractType",
    "Document",
    "Experience",
    "ExperienceLevel",
    "ExperiencePreference",
    "Job",
    "JobMatch",
    "JobSkill",
    "JobSource",
    "JobTitle",
    "JobUserState",
    "MatchingSettings",
    "N8nWebhookEvent",
    "Notification",
    "NotificationSettings",
    "Profile",
    "ProfileSkill",
    "Recruiter",
    "RecruiterResponse",
    "RefreshToken",
    "ScrapingRun",
    "SearchPreference",
    "Skill",
    "SkillCategory",
    "Source",
    "User",
    "preference_contract_types",
]
