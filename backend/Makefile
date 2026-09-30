# Commandes du projet. Tapez "make help" pour la liste.
# Les commandes locales utilisent le virtualenv .venv (créé par "make install").

VENV ?= .venv
PYTHON := $(VENV)/bin/python
COMPOSE := docker compose
COMPOSE_DEV := docker compose -f docker-compose.yml -f docker-compose.dev.yml
SRC := app tests scripts alembic

.DEFAULT_GOAL := help
.PHONY: help env install lint format typecheck test test-unit test-docker migrate revision downgrade \
	seed seed-dev dev worker docker-build docker-up docker-down docker-logs docker-ps dev-docker \
	n8n-import clean

help: ## Affiche cette aide
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

env: ## Crée le fichier .env avec des secrets aléatoires (si absent)
	python3 scripts/generate_env.py

install: ## Crée le virtualenv (Python 3.12) et installe les dépendances de dev
	uv venv --python 3.12 $(VENV) || python3.12 -m venv $(VENV)
	uv pip install --python $(PYTHON) -r requirements-dev.txt || $(PYTHON) -m pip install -r requirements-dev.txt

lint: ## Vérifie le code (Ruff + Black + MyPy)
	$(VENV)/bin/ruff check $(SRC)
	$(VENV)/bin/black --check $(SRC)
	$(VENV)/bin/mypy app scripts

format: ## Formate le code (Black + corrections Ruff)
	$(VENV)/bin/ruff check --fix $(SRC)
	$(VENV)/bin/black $(SRC)

typecheck: ## Vérifie les types (MyPy)
	$(VENV)/bin/mypy app scripts

test: ## Lance tous les tests (démarre PostgreSQL et Redis si besoin)
	$(COMPOSE) up -d --wait postgres redis
	$(VENV)/bin/pytest

test-unit: ## Lance uniquement les tests unitaires (sans base de données)
	$(VENV)/bin/pytest tests/unit

test-docker: ## Lance les tests dans un conteneur (image de dev)
	$(COMPOSE_DEV) up -d --wait postgres redis
	$(COMPOSE_DEV) run --rm --no-deps api pytest

migrate: ## Applique les migrations (refuse les migrations destructives) + référentiels
	$(PYTHON) -m scripts.migrate

revision: ## Crée une migration : make revision m="description"
	$(VENV)/bin/alembic revision --autogenerate -m "$(m)"

downgrade: ## Annule la dernière migration (à utiliser avec précaution)
	$(VENV)/bin/alembic downgrade -1

seed: ## Charge les données de référence
	$(PYTHON) -m scripts.seed

seed-dev: ## Charge les référentiels + un compte et des offres de démonstration
	$(PYTHON) -m scripts.seed --dev

dev: ## Lance l'API en local avec rechargement automatique (PostgreSQL/Redis via Docker)
	$(COMPOSE) up -d --wait postgres redis
	$(VENV)/bin/uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

worker: ## Lance le worker Celery en local
	$(VENV)/bin/celery -A app.worker worker --loglevel=INFO

docker-build: ## Construit l'image Docker
	$(COMPOSE) build

docker-up: ## Démarre toute la stack (API, worker, PostgreSQL, Redis, n8n)
	$(COMPOSE) up -d --build

docker-down: ## Arrête la stack (les données sont conservées dans les volumes)
	$(COMPOSE) down

docker-logs: ## Affiche les logs de l'API et du worker
	$(COMPOSE) logs -f api worker

docker-ps: ## État des conteneurs et de leurs healthchecks
	$(COMPOSE) ps

dev-docker: ## Stack de développement (hot reload, logs lisibles)
	$(COMPOSE_DEV) up --build

n8n-import: ## Importe (ou met à jour) les workflows n8n du dossier n8n/workflows
	$(COMPOSE) exec n8n n8n import:workflow --separate --input=/home/node/workflows

clean: ## Supprime les caches Python
	find . -type d \( -name __pycache__ -o -name .pytest_cache -o -name .mypy_cache -o -name .ruff_cache \) -prune -exec rm -rf {} +
