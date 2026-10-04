# PATCH 10 — check-ins trimestriels N/N+1 (roadmap PRO) : points forts,
# axes d'amélioration, décision, date de réunion. Périmètre relationnel.
from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.rating import Checkin, Salarie
from app.services.hierarchie import collaborateurs_directs, collaborateurs_indirects

router = APIRouter(prefix="/api/checkins", tags=["Check-ins"])


class CheckinIn(BaseModel):
    salarie_id: int
    trimestre: int
    annee: int
    points_forts: str
    axes_amelioration: str


def _perimetre(db: Session, user: Salarie) -> list[int]:
    ids = [s.id for s in collaborateurs_directs(db, user.id)]
    ids += [s.id for s in collaborateurs_indirects(db, user.id)]
    return ids


def _dict(db: Session, c: Checkin) -> dict:
    s = db.query(Salarie).get(c.salarie_id)
    a = db.query(Salarie).get(c.auteur_id)
    return {
        "id": c.id, "salarie_id": c.salarie_id,
        "matricule": s.matricule if s else "?", "nom": s.full_name if s else "?",
        "trimestre": c.trimestre, "annee": c.annee,
        "points_forts": c.points_forts, "axes_amelioration": c.axes_amelioration,
        "decision": c.decision, "date_reunion": c.date_reunion,
        "auteur": a.full_name if a else "?",
    }


@router.get("/collaborateurs")
def collaborateurs(db: Session = Depends(get_db),
                   user: Salarie = Depends(get_current_user)):
    if user.is_admin:
        cols = db.query(Salarie).filter(
            Salarie.is_active.is_(True), Salarie.is_admin.is_(False)).all()
    else:
        cols = collaborateurs_directs(db, user.id) + collaborateurs_indirects(db, user.id)
    return [{"id": s.id, "matricule": s.matricule, "nom": s.full_name} for s in cols]


@router.get("")
def lister(trimestre: int | None = None, annee: int | None = None,
           db: Session = Depends(get_db), user: Salarie = Depends(get_current_user)):
    q = db.query(Checkin)
    if not user.is_admin:
        per = _perimetre(db, user)
        per.append(user.id)
        q = q.filter(Checkin.salarie_id.in_(per))
    if trimestre:
        q = q.filter(Checkin.trimestre == trimestre)
    if annee:
        q = q.filter(Checkin.annee == annee)
    return [_dict(db, c) for c in q.order_by(Checkin.annee.desc(), Checkin.trimestre.desc()).all()]


@router.post("", status_code=201)
def creer(p: CheckinIn, db: Session = Depends(get_db),
          user: Salarie = Depends(get_current_user)):
    if not (1 <= p.trimestre <= 4) or p.annee < 2000:
        raise HTTPException(422, "Trimestre (1-4) ou année invalide.")
    if not p.points_forts.strip() or not p.axes_amelioration.strip():
        raise HTTPException(422, "Points forts et axes d'amélioration obligatoires.")
    if not user.is_admin:
        per = _perimetre(db, user)
        if p.salarie_id not in per and p.salarie_id != user.id:
            raise HTTPException(403, "Ce salarié n'est pas dans votre périmètre.")
    c = Checkin(salarie_id=p.salarie_id, auteur_id=user.id,
                trimestre=p.trimestre, annee=p.annee,
                points_forts=p.points_forts.strip(),
                axes_amelioration=p.axes_amelioration.strip())
    db.add(c); db.commit(); db.refresh(c)
    return _dict(db, c)


@router.post("/{checkin_id}/cloturer")
def cloturer(checkin_id: int, db: Session = Depends(get_db),
             user: Salarie = Depends(get_current_user)):
    c = db.query(Checkin).get(checkin_id)
    if not c:
        raise HTTPException(404, "Check-in introuvable.")
    if not user.is_admin and c.auteur_id != user.id:
        raise HTTPException(403, "Seul l'auteur (ou l'Admin) peut clôturer.")
    c.decision = "Clôturé"
    c.date_reunion = date.today()
    db.commit()
    return {"detail": "Check-in clôturé."}
