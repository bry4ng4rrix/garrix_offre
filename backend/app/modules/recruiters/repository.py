import uuid

from sqlalchemy import Select, func, or_, select

from app.modules.recruiters.models import Recruiter
from app.shared.repository import BaseRepository


class RecruiterRepository(BaseRepository[Recruiter]):
    model = Recruiter

    def get_by_email(self, email: str) -> Recruiter | None:
        return self.session.scalar(
            select(Recruiter).where(func.lower(Recruiter.email) == email.lower()).limit(1)
        )

    def get_by_name_and_company(self, name: str, company_id: uuid.UUID | None) -> Recruiter | None:
        stmt = select(Recruiter).where(func.lower(Recruiter.name) == name.lower())
        stmt = stmt.where(
            Recruiter.company_id == company_id if company_id else Recruiter.company_id.is_(None)
        )
        return self.session.scalar(stmt.limit(1))

    def search_query(
        self, search: str | None = None, company_id: uuid.UUID | None = None
    ) -> Select[Recruiter]:
        stmt = select(Recruiter).order_by(Recruiter.name, Recruiter.last_name)
        if search:
            pattern = f"%{search}%"
            stmt = stmt.where(
                or_(
                    Recruiter.name.ilike(pattern),
                    Recruiter.first_name.ilike(pattern),
                    Recruiter.last_name.ilike(pattern),
                    Recruiter.email.ilike(pattern),
                )
            )
        if company_id:
            stmt = stmt.where(Recruiter.company_id == company_id)
        return stmt
