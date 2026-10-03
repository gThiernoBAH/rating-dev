# 2026-10-02 — Mon espace (M2) : bandeau contexte (nom, matricule, dept, section,
# N+1, campagne active) + blocs selon le rôle + compteur notifications.
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.rating import Campagne, Salarie
from app.services.hierarchie import (
    a_des_collaborateurs_directs, a_des_collaborateurs_indirects,
)

router = APIRouter(prefix="/api/espace", tags=["Mon espace"])


@router.get("")
def mon_espace(db: Session = Depends(get_db),
               user: Salarie = Depends(get_current_user)):
    n1 = db.query(Salarie).get(user.n1_id) if user.n1_id else None
    campagnes = db.query(Campagne).filter(
        Campagne.statut == "Ouverte").order_by(Campagne.exercice.desc()).all()
    return {
        "matricule": user.matricule,
        "nom": user.full_name,
        "email": user.email,
        "n1": n1.full_name if n1 else None,
        "campagnes_actives": [{"id": c.id, "nom": c.nom, "exercice": c.exercice}
                              for c in campagnes],
        "roles": {
            "admin": user.is_admin,
            "n1": a_des_collaborateurs_directs(db, user.id),
            "n2": a_des_collaborateurs_indirects(db, user.id),
        },
    }
