# PATCH 10 — API relances : aperçu des retardataires + envoi (Admin).
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import require_admin
from app.models.rating import Campagne, Salarie
from app.services.relances import envoyer_relances, retardataires

router = APIRouter(prefix="/api/relances", tags=["Relances"])


@router.get("/campagne/{campagne_id}/apercu")
def apercu(campagne_id: int, db: Session = Depends(get_db),
           admin: Salarie = Depends(require_admin)):
    c = db.query(Campagne).get(campagne_id)
    if not c:
        raise HTTPException(404, "Campagne introuvable.")
    ret = retardataires(db, c)
    out = {}
    for etape, fiches in ret.items():
        out[etape] = [{"numero": e.numero, "matricule": s.matricule,
                       "nom": s.full_name} for e, s, _ in fiches]
    return out


@router.post("/campagne/{campagne_id}/envoyer")
def envoyer(campagne_id: int, db: Session = Depends(get_db),
            admin: Salarie = Depends(require_admin)):
    c = db.query(Campagne).get(campagne_id)
    if not c:
        raise HTTPException(404, "Campagne introuvable.")
    if c.statut != "Ouverte":
        raise HTTPException(422, "Les relances ne concernent que les campagnes Ouvertes.")
    return envoyer_relances(db, c)
