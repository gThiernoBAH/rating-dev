# HIF-RATING (rating-dev)

Réécriture de HIF-RATING 20 (Delphi/SQL Server) en FastAPI + Vue 3 + PostgreSQL.
Référence : cahier des charges v2 du 01/10/2026. Conventions calquées sur vusine-dev.

## Démarrage (dev)

    # 1. Base de données
    cd backend
    cp .env.example .env     # renseigner POSTGRES_PASSWORD + AUTH_SECRET_KEY (>=32 car.)
    bash scripts/reset_ratingdb_dev.sh

    # 2. Backend (port 8003)
    python -m venv .venv && source .venv/bin/activate
    pip install -r requirements.txt
    uvicorn app.main:app --reload --port 8003
    # Swagger : http://localhost:8003/docs

    # 3. Admin initial
    python scripts/create_admin.py ADMIN0001 'Admin RH'

    # 4. Référentiel + import Excel de migration
    python scripts/import_referentiel.py migration.xlsx

    # 5. Frontend (port 5176, proxy /api -> 8003)
    cd ../frontend
    npm install && npm run dev

    # 6. Tests golden du moteur de notation
    cd ../backend && pytest tests/ -q

## État du projet (2026-10-02 — livraison complète)

- [x] Étape 1 — schema.sql complet (tables, contraintes, vues) + params.sql
- [x] Étape 2 — squelette backend + auth matricule/JWT/throttle + create_admin.py
- [x] Étape 3 — Référentiel : CRUD API complet (M5) + import Excel openpyxl
- [x] Étape 4 — Campagnes : création, ouverture, génération idempotente par famille
      avec rapport, rattrapage, clôture (M6)
- [x] Étape 5 — Fiche d'évaluation M4 : onglets profils, grille grisée par rôle,
      QCM double-clic (libellé affiché, note cachée), commentaire obligatoire,
      cadenas avec contrôle de complétude, séquencement strict N -> N+1 -> N+2,
      approbation N+2 (sans re-notation), déverrouillage Admin justifié
- [x] Étape 6 — Tableau M3 : 3 sections selon le rôle, blocages par statuts
- [x] Étape 7 — Notations M4bis : moteur (COEFF./NOTE/VALEUR/étoiles/totaux/
      note globale /5/appréciation par paliers) + golden tests pytest + badge divergence
- [x] Étape 8 — Navigation M3bis : GRAPHE salarié vs section, RECAP,
      benchmark inter-sections, historique inter-exercices
- [x] Étape 9 — Tableaux de bord M7 : avancement par section, retardataires, anomalies
- [x] Étape 10 — Notifications : cloche + API (mail/Telegram via service, WhatsApp prévu)
- [x] Étape 11 — Déploiement : deployer.sh, sauvegarder.sh (pg_dump quotidien),
      nginx-rating.conf, rating-api.service, README_DEPLOIEMENT.md

## Écrans livrés

M1 Connexion · M2 Mon espace · M3 Evaluations (3 sections) · M4 Fiche (pivot) ·
M4bis Notations · M5 Paramétrage · M6 Campagnes · M7 Dashboards · M3bis Navigation.
