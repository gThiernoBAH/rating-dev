# 2026-10-02 — campagnes (M6) : création, ouverture, génération idempotente par
# famille avec rapport, rattrapage, clôture (tout se fige), déverrouillage Admin justifié.
from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user, require_admin
from app.models.rating import Campagne, Salarie
from app.schemas.campagne import CampagneIn, CampagneOut, GenerationIn, GenerationReport
from app.schemas.common import MessageResponse
from app.services.audit import log_action
from app.services.campagne import generer_fiches

router = APIRouter(prefix="/api/campagnes", tags=["Campagnes"])


@router.get("", response_model=list[CampagneOut])
def list_campagnes(db: Session = Depends(get_db),
                   user: Salarie = Depends(get_current_user)):
    return db.query(Campagne).order_by(Campagne.exercice.desc()).all()


@router.post("", response_model=CampagneOut, status_code=201)
def create_campagne(p: CampagneIn, db: Session = Depends(get_db),
                    admin: Salarie = Depends(require_admin)):
    if p.date_cloture < p.date_ouverture:
        raise HTTPException(422, "La clôture doit suivre l'ouverture.")
    obj = Campagne(**p.model_dump(), statut="Brouillon")
    db.add(obj); db.commit(); db.refresh(obj)
    log_action(db, auteur_id=admin.id, action="CREATE", table_cible="campagnes",
               enregistrement_id=obj.id)
    db.commit()
    return obj


@router.post("/{campagne_id}/ouvrir", response_model=CampagneOut)
def ouvrir(campagne_id: int, db: Session = Depends(get_db),
           admin: Salarie = Depends(require_admin)):
    c = db.query(Campagne).get(campagne_id)
    if not c:
        raise HTTPException(404, "Campagne introuvable.")
    if c.statut != "Brouillon":
        raise HTTPException(409, f"Statut actuel : {c.statut}.")
    if date.today() < c.date_ouverture or date.today() > c.date_cloture:
        raise HTTPException(422, "Hors des dates d'ouverture/clôture.")
    c.statut = "Ouverte"
    db.commit(); db.refresh(c)
    return c


@router.post("/{campagne_id}/generer", response_model=GenerationReport)
def generer(campagne_id: int, p: GenerationIn, db: Session = Depends(get_db),
            admin: Salarie = Depends(require_admin)):
    """Génération automatique idempotente par famille cochée (rapport complet §4)."""
    c = db.query(Campagne).get(campagne_id)
    if not c:
        raise HTTPException(404, "Campagne introuvable.")
    if c.statut != "Ouverte":
        raise HTTPException(409, "La génération exige une campagne Ouverte.")
    if any(f not in (1, 2, 3) for f in p.familles):
        raise HTTPException(422, "familles : sous-ensemble de [1, 2, 3].")
    rap = generer_fiches(db, c, p.familles, rattrapage=p.rattrapage)
    log_action(db, auteur_id=admin.id, action="GENERER_FICHES",
               table_cible="evaluations", enregistrement_id=c.id,
               apres=rap.model_dump())
    db.commit()
    return rap


@router.post("/{campagne_id}/cloturer", response_model=CampagneOut)
def cloturer_campagne(campagne_id: int, db: Session = Depends(get_db),
                      admin: Salarie = Depends(require_admin)):
    """Clôture : tout se fige, même les fiches non clôturées (elles restent en l'état)."""
    c = db.query(Campagne).get(campagne_id)
    if not c:
        raise HTTPException(404, "Campagne introuvable.")
    if c.statut != "Ouverte":
        raise HTTPException(409, f"Statut actuel : {c.statut}.")
    c.statut = "Clôturée"
    db.commit(); db.refresh(c)
    return c
