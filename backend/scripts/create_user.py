"""Crée un compte utilisateur (ou réinitialise un compte existant) en ligne de commande.

    docker compose exec api python -m scripts.create_user --email collegue@exemple.com
    docker compose exec api python -m scripts.create_user --email vous@exemple.com --admin

Le mot de passe est demandé au clavier (jamais passé en argument, pour ne pas apparaître
dans l'historique du shell). Si le compte existe déjà, son mot de passe est remplacé et il
est réactivé ; `--admin` le promeut administrateur (un administrateur n'est jamais rétrogradé
par ce script). Utile quand ALLOW_REGISTRATION=false (serveur public).
"""

import argparse
import getpass
import sys
from collections.abc import Sequence

from pydantic import EmailStr, TypeAdapter, ValidationError

from app.core.database import session_scope
from app.core.security import hash_password
from app.modules import models  # noqa: F401 - enregistre tous les modèles
from app.modules.users.models import User
from app.modules.users.repository import UserRepository
from app.modules.users.schemas import validate_password_strength


def main(argv: Sequence[str] | None = None, *, force_admin: bool = False) -> int:
    parser = argparse.ArgumentParser(description="Crée ou réinitialise un compte utilisateur")
    parser.add_argument("--email", required=True)
    if not force_admin:
        parser.add_argument("--admin", action="store_true", help="Donne les droits administrateur")
    parser.add_argument(
        "--password-stdin", action="store_true", help="Lit le mot de passe sur l'entrée standard"
    )
    args = parser.parse_args(argv)
    is_admin = force_admin or args.admin
    role = "Administrateur" if is_admin else "Utilisateur"

    try:
        email = TypeAdapter(EmailStr).validate_python(args.email).lower()
    except ValidationError:
        print("Adresse email invalide.", file=sys.stderr)
        return 1
    password = (
        sys.stdin.readline().strip() if args.password_stdin else getpass.getpass("Mot de passe : ")
    )
    if not args.password_stdin and password != getpass.getpass("Confirmez : "):
        print("Les mots de passe ne correspondent pas.", file=sys.stderr)
        return 1
    try:
        validate_password_strength(password)
    except ValueError as exc:
        print(exc, file=sys.stderr)
        return 1

    with session_scope() as session:
        users = UserRepository(session)
        user = users.get_by_email(email)
        if user is None:
            users.add(
                User(email=email, hashed_password=hash_password(password), is_superuser=is_admin)
            )
            print(f"{role} créé : {email}")
        else:
            user.hashed_password = hash_password(password)
            user.is_active = True
            if is_admin:
                user.is_superuser = True
            print(f"Compte existant mis à jour (mot de passe remplacé, compte actif) : {email}")
        session.commit()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
