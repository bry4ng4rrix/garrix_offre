#!/usr/bin/env bash
# Déploie le backend sur un serveur (VPS) : copie du code puis (re)démarrage de la stack.
#
#   VPS_HOST=185.215.167.79 VPS_USER=allsafe SSH_KEY=~/.ssh/garrix_offre_deploy scripts/deploy.sh
#
# Variables : VPS_HOST, VPS_USER (obligatoires), VPS_PATH (défaut : garrix-offre dans le dossier
# personnel), SSH_KEY (clé privée), API_PORT (port public de l'API, défaut : 8000),
# IMPORT_N8N_WORKFLOWS=true pour (ré)importer les workflows n8n.
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
ssh "${SSH_OPTS[@]}" "$TARGET" bash -s -- "$VPS_PATH" "${IMPORT_N8N_WORKFLOWS:-false}" "$VPS_HOST" <<'REMOTE'
set -euo pipefail
cd "$1"
import_workflows="$2"
vps_host="$3"
dc() { docker compose -f docker-compose.yml -f docker-compose.prod.yml "$@" < /dev/null; }
if [ ! -f .env ]; then
  # Premier déploiement : secrets aléatoires + réglages de production.
  python3 scripts/generate_env.py
  sed -i \
    -e 's/^APP_ENV=.*/APP_ENV=production/' \
    -e 's/^LOG_FORMAT=.*/LOG_FORMAT=json/' \
    -e 's/^ALLOW_REGISTRATION=.*/ALLOW_REGISTRATION=false/' \
    -e 's/^CORS_ORIGINS=.*/CORS_ORIGINS=/' .env
  import_workflows=true
fi
# URL publique de n8n (affichée dans les nœuds Webhook).
if ! grep -q '^N8N_PUBLIC_URL=.' .env; then
  n8n_port="$(sed -n 's/^N8N_PORT=\([0-9]*\).*/\1/p' .env)"
  sed -i '/^N8N_PUBLIC_URL=/d' .env
  echo "N8N_PUBLIC_URL=http://$vps_host:${n8n_port:-5678}/" >> .env
fi
# nginx n'est plus utilisé (profil "proxy") : supprime l'ancien conteneur s'il existe encore.
dc rm --stop --force nginx > /dev/null 2>&1 || true
# dc() ajoute "< /dev/null" : sans cela, docker compose lirait la suite du script sur l'entrée standard.
dc up -d --build --wait --remove-orphans
if [ "$import_workflows" = "true" ]; then
  dc exec -T n8n n8n import:workflow --separate --input=/home/node/workflows
fi
docker image prune -f > /dev/null < /dev/null
dc ps
REMOTE

echo "==> Vérification"
curl --fail --silent --show-error --max-time 20 "http://$VPS_HOST:${API_PORT:-8000}/ready"
echo
