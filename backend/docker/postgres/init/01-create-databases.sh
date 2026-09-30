#!/bin/sh
# Exécuté UNE SEULE FOIS, à la création du volume PostgreSQL.
# Crée la base de n8n et la base utilisée par les tests (pytest).
set -e

create_database() {
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
SELECT 'CREATE DATABASE "$1"' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$1')\gexec
EOSQL
}

create_database "${N8N_DB_NAME:-n8n}"
create_database "${POSTGRES_DB}_test"
