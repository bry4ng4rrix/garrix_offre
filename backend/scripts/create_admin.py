"""Crée un compte administrateur (ou promeut un compte existant) en ligne de commande.

    docker compose exec api python -m scripts.create_admin --email vous@exemple.com

Raccourci de `python -m scripts.create_user --admin` (voir ce script pour les détails).
"""

from collections.abc import Sequence

from scripts import create_user


def main(argv: Sequence[str] | None = None) -> int:
    return create_user.main(argv, force_admin=True)


if __name__ == "__main__":
    raise SystemExit(main())
