#!/usr/bin/env bash
# Déploie le backend sur un serveur (VPS) : copie du code puis (re)démarrage de la stack.
#
#   VPS_HOST=185.215.167.79 VPS_USER=allsafe SSH_KEY=~/.ssh/garrix_offre_deploy scripts/deploy.sh
#
# Variables : VPS_HOST, VPS_USER (obligatoires), VPS_PATH (défaut : garrix-offre dans le dossier
# personnel), SSH_KEY (clé privée), NGINX_PORT (défaut : 80), IMPORT_N8N_WORKFLOWS=true pour
# (ré)importer les workflows n8n.
# Utilisé aussi par la CI/CD GitHub Actions (.github/workflows/backend.yml).
set -euo pipefail
cd "$(dirname "$0")/.."

: "${VPS_HOST:?VPS_HOST manquant}"
: "${VPS_USER:?VPS_USER manquant}"
VPS_PATH="${VPS_PATH:-garrix-offre}"
TARGET="$VPS_USER@$VPS_HOST"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=20)
if [[ -n "${SSH_KEY:-}" ]]; then
  SSH_OPTS+=(-i "$SSH_KEY")
fi

echo "==> Copie du code vers $TARGET:$VPS_PATH"
tar --exclude=./.env --exclude=./.venv --exclude=./storage --exclude=./.git \
  --exclude='__pycache__' --exclude=.pytest_cache --exclude=.mypy_cache --exclude=.ruff_cache \
  -czf - . | ssh "${SSH_OPTS[@]}" "$TARGET" "mkdir -p '$VPS_PATH' && tar -xzf - -C '$VPS_PATH'"

echo "==> Démarrage de la stack"
ssh "${SSH_OPTS[@]}" "$TARGET" bash -s -- "$VPS_PATH" "${IMPORT_N8N_WORKFLOWS:-false}" <<'REMOTE'
set -euo pipefail
cd "$1"
import_workflows="$2"
if [ ! -f .env ]; then
  # Premier déploiement : secrets aléatoires + réglages de production.
  python3 scripts/generate_env.py
  sed -i \
    -e 's/^APP_ENV=.*/APP_ENV=production/' \
    -e 's/^LOG_FORMAT=.*/LOG_FORMAT=json/' \
    -e 's/^ALLOW_REGISTRATION=.*/ALLOW_REGISTRATION=false/' \
    -e 's/^CORS_ORIGINS=.*/CORS_ORIGINS=/' \
    -e 's/^NGINX_PORT=.*/NGINX_PORT=80/' .env
  import_workflows=true
fi
# "< /dev/null" : sans cela, docker compose lirait la suite de ce script sur l'entrée standard.
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build --wait --remove-orphans < /dev/null
if [ "$import_workflows" = "true" ]; then
  docker compose exec -T n8n n8n import:workflow --separate --input=/home/node/workflows < /dev/null
fi
# Recharge la configuration nginx (fichier monté depuis docker/nginx/default.conf).
docker compose -f docker-compose.yml -f docker-compose.prod.yml exec -T nginx nginx -s reload < /dev/null
docker image prune -f > /dev/null < /dev/null
docker compose -f docker-compose.yml -f docker-compose.prod.yml ps < /dev/null
REMOTE

echo "==> Vérification"
curl --fail --silent --show-error --max-time 20 "http://$VPS_HOST:${NGINX_PORT:-80}/ready"
echo
