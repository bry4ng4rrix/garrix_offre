from sqlalchemy import Select, func, select

from app.modules.users.models import User
from app.shared.repository import BaseRepository


class UserRepository(BaseRepository[User]):
    model = User

    def get_by_email(self, email: str) -> User | None:
        return self.session.scalar(select(User).where(User.email == email.lower()))

    def count(self) -> int:
        return self.session.scalar(select(func.count()).select_from(User)) or 0

    def list_active(self) -> list[User]:
        return list(self.session.scalars(select(User).where(User.is_active.is_(True))))

    def list_active_superusers(self) -> list[User]:
        stmt = select(User).where(User.is_active.is_(True), User.is_superuser.is_(True))
        return list(self.session.scalars(stmt))

    def list_query(self) -> Select[tuple[User]]:
        return select(User).order_by(User.created_at)
