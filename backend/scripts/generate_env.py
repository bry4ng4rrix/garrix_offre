"""Crée le fichier .env à partir de .env.example en générant des secrets aléatoires.

Usage : python scripts/generate_env.py [--force]

- Chaque valeur commençant par "change-me" est remplacée par un secret aléatoire.
- Le mot de passe PostgreSQL généré est aussi reporté dans DATABASE_URL.
- Sans --force, un .env existant n'est jamais écrasé.
"""

import re
import secrets
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXAMPLE = ROOT / ".env.example"
TARGET = ROOT / ".env"

LINE_PATTERN = re.compile(r"^(?P<key>[A-Z0-9_]+)=(?P<value>\S*)(?P<rest>.*)$")


def main() -> int:
    force = "--force" in sys.argv
    if TARGET.exists() and not force:
        print(".env existe déjà (utilisez --force pour le régénérer).")
        return 0

    values: dict[str, str] = {}
    output_lines = []
    for line in EXAMPLE.read_text(encoding="utf-8").splitlines():
        match = LINE_PATTERN.match(line)
        if match and match["value"].startswith("change-me"):
            # Alphanumérique uniquement : sûr dans une URL de connexion PostgreSQL.
            secret = secrets.token_hex(32)
            values[match["key"]] = secret
            line = f"{match['key']}={secret}{match['rest']}"
        output_lines.append(line)

    content = "\n".join(output_lines) + "\n"
    postgres_password = values.get("POSTGRES_PASSWORD")
    if postgres_password:
        content = content.replace("change-me-postgres-password", postgres_password)

    TARGET.write_text(content, encoding="utf-8")
    TARGET.chmod(0o600)
    print(f".env créé ({len(values)} secrets générés). Pensez à compléter Telegram / SMTP / IA.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
