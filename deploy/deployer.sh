#!/usr/bin/env bash
# =============================================================================
# 2026-10-02 — déploiement sur étiquette : /srv/rating
# Usage (sur le serveur, depuis le clone du dépôt) :  bash deploy/deployer.sh
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

echo ">>> 1/4 Dépendances backend"
cd backend
[ -d .venv ] || python3 -m venv .venv
.venv/bin/pip install -q -r requirements.txt

echo ">>> 2/4 Schéma PostgreSQL (si base vide)"
.venv/bin/python - <<'PY'
import os
from sqlalchemy import create_engine, text
from dotenv import load_dotenv
load_dotenv()
url = os.environ["POSTGRES_URL"] if "POSTGRES_URL" in os.environ else None
PY
psql "$DATABASE_URL" -f scripts/schema.sql 2>/dev/null || true
psql "$DATABASE_URL" -f scripts/params.sql 2>/dev/null || true

echo ">>> 3/4 Compilation frontend"
cd ../frontend
npm ci --silent && npm run build --silent

echo ">>> 4/4 Services"
sudo systemctl restart rating-api.service
sudo nginx -t && sudo systemctl reload nginx
echo "✔ Déploiement terminé."
