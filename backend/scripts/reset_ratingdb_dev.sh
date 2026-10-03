#!/usr/bin/env bash
# =============================================================================
# 2026-10-02 — réinitialise ratingdb_dev (DÉV UNIQUEMENT).
# ⚠ SUPPRIME ET RECRÉE LA BASE — aucun mot de passe en clair (lu dans .env).
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

# .env jamais versionné ; source silencieuse s'il est absent en CI
if [ -f .env ]; then set -a; . ./.env; set +a; fi

: "${POSTGRES_DB:=ratingdb_dev}" "${POSTGRES_USER:=postgres}"

read -rp "⚠  Cela SUPPRIMERA la base '${POSTGRES_DB}'. Confirmer ? (oui/non) " ans
[ "$ans" = "oui" ] || { echo "Abandon."; exit 1; }

psql -h "${POSTGRES_HOST:-localhost}" -U "$POSTGRES_USER" -d postgres \
  -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};"
psql -h "${POSTGRES_HOST:-localhost}" -U "$POSTGRES_USER" -d postgres \
  -c "CREATE DATABASE ${POSTGRES_DB};"

psql -h "${POSTGRES_HOST:-localhost}" -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -f scripts/schema.sql
psql -h "${POSTGRES_HOST:-localhost}" -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -f scripts/params.sql

echo "✔ Base ${POSTGRES_DB} réinitialisée (schema + params)."
echo "  Créez l'admin :  python scripts/create_admin.py ADMIN0001 'Admin RH'"
