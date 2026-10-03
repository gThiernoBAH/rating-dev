#!/usr/bin/env bash
# =============================================================================
# 2026-10-02 — pg_dump quotidien (cron 02:00) : /var/backups/ratingdb/
# Ajouter au crontab :  0 2 * * * /srv/rating/deploy/sauvegarder.sh
# =============================================================================
set -euo pipefail
DEST=/var/backups/ratingdb
mkdir -p "$DEST"
FICHIER="$DEST/ratingdb-$(date +%Y%m%d-%H%M).dump"
pg_dump -Fc "$DATABASE_URL" -f "$FICHIER"
# rétention 30 jours
find "$DEST" -name 'ratingdb-*.dump' -mtime +30 -delete
echo "✔ Sauvegarde : $FICHIER"
