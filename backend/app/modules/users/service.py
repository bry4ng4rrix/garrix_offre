import logging
import uuid

from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError, ConflictError, NotFoundError
from app.core.security import hash_password, verify_password
from app.modules.users.models import User
from app.modules.users.repository import UserRepository
from app.modules.users.schemas import UserAdminUpdate
from app.shared.pagination import PaginationParams

logger = logging.getLogger("app.auth")


class UserService:
    """Création et administration des comptes utilisateurs."""

    def __init__(self, session: Session) -> None:
        self.session = session
        self.users = UserRepository(session)

    def create_user(self, email: str, password: str) -> User:
        email = email.lower()
        if self.users.get_by_email(email):
            raise ConflictError("A user with this email already exists", code="EMAIL_ALREADY_USED")
        # Le tout premier compte devient administrateur de l'instance.
        is_first_user = self.users.count() == 0
        user = self.users.add(
            User(email=email, hashed_password=hash_password(password), is_superuser=is_first_user)
        )
        logger.info("User created", extra={"user_id": str(user.id), "superuser": is_first_user})
        return user

    def get_user(self, user_id: uuid.UUID) -> User:
        user = self.users.get(user_id)
        if not user:
            raise NotFoundError("User not found", code="USER_NOT_FOUND")
        return user

    def list_users(self, pagination: PaginationParams) -> tuple[list[User], int]:
        return self.users.paginate(self.users.list_query(), pagination)

    def admin_update(self, user_id: uuid.UUID, data: UserAdminUpdate, admin: User) -> User:
        user = self.get_user(user_id)
        if user.id == admin.id and (data.is_active is False or data.is_superuser is False):
            raise BusinessRuleError(
                "You cannot deactivate or demote your own account", code="CANNOT_MODIFY_SELF"
            )
        for field, value in data.model_dump(exclude_unset=True).items():
            setattr(user, field, value)
        self.session.commit()
        return user

    def change_password(self, user: User, current_password: str, new_password: str) -> None:
        if not verify_password(current_password, user.hashed_password):
            raise BusinessRuleError("Current password is incorrect", code="INVALID_PASSWORD")
        user.hashed_password = hash_password(new_password)
        self.session.commit()
        logger.info("Password changed", extra={"user_id": str(user.id)})
