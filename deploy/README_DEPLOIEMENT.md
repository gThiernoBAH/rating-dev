# Déploiement HIF-RATING (prod)

2026-10-02 — cible : /srv/rating (clone du dépôt sur étiquette).

## Prérequis

- Ubuntu 22.04+, Python 3.11+, Node 18+, PostgreSQL 15+, nginx
- Rôle dédié : CREATE USER rating WITH PASSWORD '...'; CREATE DATABASE ratingdb OWNER rating;

## Étapes

1. git clone <depot> /srv/rating && cd /srv/rating && git checkout <etiquette>
2. cp deploy/env.prod.example backend/.env    # renseigner les secrets
3. psql -h localhost -U rating -d ratingdb -f backend/scripts/schema.sql
4. psql -h localhost -U rating -d ratingdb -f backend/scripts/params.sql
5. cd backend && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
6. .venv/bin/python scripts/create_admin.py ADMIN0001 'Admin RH'
7. sudo cp deploy/rating-api.service /etc/systemd/system/ && sudo systemctl enable --now rating-api
8. cd ../frontend && npm ci && npm run build
9. sudo cp deploy/nginx-rating.conf /etc/nginx/sites-available/rating && activer
10. Crontab sauvegarde : 0 2 * * * /srv/rating/deploy/sauvegarder.sh

## Ports

- API : 127.0.0.1:8103 (systemd, jamais exposé directement)
- Frontend : nginx 443 (HTTPS) relaie /api/ -> 8103 ; CORS vide
