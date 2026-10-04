# PATCH 10 — objectifs OKR trimestriels : objectif + résultats clés avec
# avancement (0-100 %). Périmètre relationnel N/N+1/N+2/Admin.
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.rating import Objectif, ObjectifKr, Salarie
from app.services.hierarchie import collaborateurs_directs, collaborateurs_indirects

router = APIRouter(prefix="/api/objectifs", tags=["Objectifs OKR"])


class ObjectifIn(BaseModel):
    salarie_id: int
    titre: str
    description: str | None = None
    trimestre: int
    annee: int


class KrIn(BaseModel):
    libelle: str


class AvancementIn(BaseModel):
    avancement: int


def _perimetre(db: Session, user: Salarie) -> list[int]:
    ids = [s.id for s in collaborateurs_directs(db, user.id)]
    ids += [s.id for s in collaborateurs_indirects(db, user.id)]
    return ids


def _dict(db: Session, o: Objectif) -> dict:
    s = db.query(Salarie).get(o.salarie_id)
    return {
        "id": o.id, "salarie_id": o.salarie_id,
        "matricule": s.matricule if s else "?", "nom": s.full_name if s else "?",
        "titre": o.titre, "description": o.description,
        "trimestre": o.trimestre, "annee": o.annee, "statut": o.statut,
        "krs": [{"id": k.id, "libelle": k.libelle, "avancement": k.avancement}
                for k in db.query(ObjectifKr)
                .filter(ObjectifKr.objectif_id == o.id)
                .order_by(ObjectifKr.id).all()],
    }


@router.get("")
def lister(trimestre: int | None = None, annee: int | None = None,
           db: Session = Depends(get_db), user: Salarie = Depends(get_current_user)):
    q = db.query(Objectif)
    if not user.is_admin:
        per = _perimetre(db, user)
        per.append(user.id)
        q = q.filter(Objectif.salarie_id.in_(per))
    if trimestre:
        q = q.filter(Objectif.trimestre == trimestre)
    if annee:
        q = q.filter(Objectif.annee == annee)
    return [_dict(db, o) for o in q.order_by(Objectif.annee.desc(), Objectif.trimestre.desc()).all()]


@router.post("", status_code=201)
def creer(p: ObjectifIn, db: Session = Depends(get_db),
          user: Salarie = Depends(get_current_user)):
    if not p.titre.strip():
        raise HTTPException(422, "Titre obligatoire.")
    if not (1 <= p.trimestre <= 4) or p.annee < 2000:
        raise HTTPException(422, "Trimestre (1-4) ou année invalide.")
    if not user.is_admin:
        per = _perimetre(db, user)
        if p.salarie_id not in per and p.salarie_id != user.id:
            raise HTTPException(403, "Ce salarié n'est pas dans votre périmètre.")
    o = Objectif(salarie_id=p.salarie_id, auteur_id=user.id,
                 titre=p.titre.strip(),
                 description=(p.description or "").strip() or None,
                 trimestre=p.trimestre, annee=p.annee)
    db.add(o); db.commit(); db.refresh(o)
    return _dict(db, o)


@router.post("/{objectif_id}/krs", status_code=201)
def ajouter_kr(objectif_id: int, p: KrIn, db: Session = Depends(get_db),
               user: Salarie = Depends(get_current_user)):
    o = db.query(Objectif).get(objectif_id)
    if not o:
        raise HTTPException(404, "Objectif introuvable.")
    if not user.is_admin and o.auteur_id != user.id:
        raise HTTPException(403, "Seul l'auteur (ou l'Admin) peut ajouter un résultat clé.")
    if not p.libelle.strip():
        raise HTTPException(422, "Libellé obligatoire.")
    db.add(ObjectifKr(objectif_id=o.id, libelle=p.libelle.strip()))
    db.commit()
    return _dict(db, o)


@router.post("/krs/{kr_id}/avancement")
def avancer(kr_id: int, p: AvancementIn, db: Session = Depends(get_db),
            user: Salarie = Depends(get_current_user)):
    k = db.query(ObjectifKr).get(kr_id)
    if not k:
        raise HTTPException(404, "Résultat clé introuvable.")
    o = db.query(Objectif).get(k.objectif_id)
    if not user.is_admin and o.auteur_id != user.id and o.salarie_id != user.id:
        raise HTTPException(403, "Non autorisé.")
    if not (0 <= p.avancement <= 100):
        raise HTTPException(422, "Avancement entre 0 et 100.")
    k.avancement = p.avancement
    db.commit()
    return {"detail": "Avancement mis à jour."}


@router.post("/{objectif_id}/cloturer")
def cloturer(objectif_id: int, db: Session = Depends(get_db),
             user: Salarie = Depends(get_current_user)):
    o = db.query(Objectif).get(objectif_id)
    if not o:
        raise HTTPException(404, "Objectif introuvable.")
    if not user.is_admin and o.auteur_id != user.id:
        raise HTTPException(403, "Seul l'auteur (ou l'Admin) peut clôturer.")
    o.statut = "Clôturé"
    db.commit()
    return {"detail": "Objectif clôturé."}
