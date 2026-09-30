from sqlalchemy import Select, or_, select

from app.modules.companies.models import Company
from app.shared.repository import BaseRepository


class CompanyRepository(BaseRepository[Company]):
    model = Company

    def get_by_normalized_name(self, normalized_name: str) -> Company | None:
        return self.session.scalar(
            select(Company).where(Company.normalized_name == normalized_name)
        )

    def search_query(
        self,
        search: str | None = None,
        city: str | None = None,
        country: str | None = None,
        industry: str | None = None,
    ) -> Select[Company]:
        stmt = select(Company).order_by(Company.name)
        if search:
            pattern = f"%{search}%"
            stmt = stmt.where(or_(Company.name.ilike(pattern), Company.description.ilike(pattern)))
        if city:
            stmt = stmt.where(Company.city.ilike(city))
        if country:
            stmt = stmt.where(Company.country.ilike(country))
        if industry:
            stmt = stmt.where(Company.industry.ilike(f"%{industry}%"))
        return stmt
