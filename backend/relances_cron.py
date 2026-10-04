# PATCH 10 — relances automatiques quotidiennes (cron). Exemple crontab :
#   0 8 * * * cd /opt/rating-dev/backend && ./venv/bin/python relances_cron.py >> relances.log 2>&1
from app.core.database import SessionLocal
from app.models.rating import Campagne
from app.services.relances import envoyer_relances

total = 0
with SessionLocal() as db:
    for c in db.query(Campagne).filter(Campagne.statut == "Ouverte").all():
        r = envoyer_relances(db, c)
        total += r["notifiees"]
        print(f"{c.nom} : {r['notifiees']} notification(s) envoyée(s), "
              f"{r['deja_relancees']} ignorée(s) (anti-spam 24 h) — "
              f"N:{r['n']} N+1:{r['n1']} N+2:{r['n2']}")
print("Relances terminées :", total)
