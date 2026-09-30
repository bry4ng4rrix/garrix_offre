# syntax=docker/dockerfile:1
#
# Image unique pour l'API, le worker Celery et le job de migration.
#   - cible "production" (par défaut) : dépendances de prod uniquement
#   - cible "dev" : + outils de test/lint, utilisée par docker-compose.dev.yml

# ---------- Base commune ----------
FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PATH="/opt/venv/bin:$PATH" \
    STORAGE_PATH=/app/storage
RUN groupadd --system --gid 1001 app \
    && useradd --system --uid 1001 --gid app --home-dir /app --shell /usr/sbin/nologin app
WORKDIR /app

# ---------- Installation des dépendances (production) ----------
FROM base AS builder
RUN python -m venv /opt/venv
COPY requirements.txt ./
RUN pip install -r requirements.txt

# ---------- Dépendances de développement ----------
FROM builder AS dev-builder
COPY requirements-dev.txt ./
RUN pip install -r requirements-dev.txt

# ---------- Image de développement ----------
FROM base AS dev
COPY --from=dev-builder /opt/venv /opt/venv
COPY --chown=app:app . .
RUN mkdir -p /app/storage && chown app:app /app/storage
USER app
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload", "--reload-dir", "app"]

# ---------- Image de production ----------
FROM base AS production
COPY --from=builder /opt/venv /opt/venv
COPY --chown=app:app alembic.ini ./
COPY --chown=app:app alembic ./alembic
COPY --chown=app:app scripts ./scripts
COPY --chown=app:app app ./app
RUN mkdir -p /app/storage && chown app:app /app/storage
USER app
EXPOSE 8000
# --proxy-headers : récupère la vraie IP client derrière nginx (FORWARDED_ALLOW_IPS).
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers --workers ${API_WORKERS:-2}"]
