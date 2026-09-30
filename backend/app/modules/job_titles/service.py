import uuid

from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, NotFoundError
from app.modules.job_titles.models import JobTitle
from app.modules.job_titles.repository import JobTitleRepository
from app.modules.job_titles.schemas import JobTitleCreate, JobTitleUpdate
from app.modules.users.models import User
from app.shared.utils import normalize_text


class JobTitleService:
    """Postes recherchés par l'utilisateur."""

    def __init__(self, session: Session) -> None:
        self.session = session
        self.repository = JobTitleRepository(session)

    def list_titles(self, user: User, enabled_only: bool = False) -> list[JobTitle]:
        return self.repository.list_for_user(user.id, enabled_only)

    def get(self, user: User, job_title_id: uuid.UUID) -> JobTitle:
        job_title = self.repository.get_for_user(job_title_id, user.id)
        if job_title is None:
            raise NotFoundError("Job title not found", code="JOB_TITLE_NOT_FOUND")
        return job_title

    def create(self, user: User, data: JobTitleCreate) -> JobTitle:
        normalized = normalize_text(data.title)
        if self.repository.get_by_normalized(user.id, normalized):
            raise ConflictError("This job title already exists", code="JOB_TITLE_EXISTS")
        job_title = self.repository.add(
            JobTitle(
                user_id=user.id,
                title=data.title,
                normalized_title=normalized,
                priority=data.priority,
                enabled=data.enabled,
            )
        )
        self.session.commit()
        return job_title

    def update(self, user: User, job_title_id: uuid.UUID, data: JobTitleUpdate) -> JobTitle:
        job_title = self.get(user, job_title_id)
        updates = data.model_dump(exclude_unset=True)
        if updates.get("title"):
            normalized = normalize_text(updates["title"])
            duplicate = self.repository.get_by_normalized(user.id, normalized)
            if duplicate and duplicate.id != job_title.id:
                raise ConflictError("This job title already exists", code="JOB_TITLE_EXISTS")
            job_title.normalized_title = normalized
        for field, value in updates.items():
            setattr(job_title, field, value)
        self.session.commit()
        return job_title

    def delete(self, user: User, job_title_id: uuid.UUID) -> None:
        self.repository.delete(self.get(user, job_title_id))
        self.session.commit()

    def sync_titles(self, user: User, titles: list[str]) -> None:
        """Utilisé par PUT /preferences : active les titres listés, désactive les autres.

        Rien n'est supprimé (la priorité de chaque titre est conservée). Pas de commit.
        """
        wanted: dict[str, str] = {}
        for title in titles:
            if normalize_text(title):
                wanted.setdefault(normalize_text(title), title.strip()[:200])
        existing = {item.normalized_title: item for item in self.repository.list_for_user(user.id)}
        for normalized, job_title in existing.items():
            job_title.enabled = normalized in wanted
        for normalized, title in wanted.items():
            if normalized not in existing:
                self.repository.add(
                    JobTitle(user_id=user.id, title=title, normalized_title=normalized)
                )
