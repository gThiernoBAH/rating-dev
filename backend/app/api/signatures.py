# PATCH 10 — signature électronique N / N+1 / N+2 (empreinte SHA-256 horodatée).
import hashlib
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.rating import Evaluation, Salarie, Signature
from app.services.evaluations import mon_role

router = APIRouter(prefix="/api/evaluations", tags=["Signatures"])


def _signatures(db: Session, evaluation_id: int) -> list[Signature]:
    return (
        db.query(Signature)
        .filter(Signature.evaluation_id == evaluation_id)
        .order_by(Signature.horodatage)
        .all()
    )


@router.get("/{evaluation_id}/signatures")
def lister(evaluation_id: int, db: Session = Depends(get_db),
           user: Salarie = Depends(get_current_user)):
    ev = db.query(Evaluation).get(evaluation_id)
    if not ev:
        raise HTTPException(404, "Fiche introuvable.")
    if mon_role(db, ev, user) is None:
        raise HTTPException(403, "Accès refusé.")
    out = []
    for s in _signatures(db, evaluation_id):
        a = db.query(Salarie).get(s.auteur_id)
        out.append({
            "id": s.id, "etape": s.etape,
            "auteur": a.full_name if a else "?",
            "date": s.horodatage.strftime("%d/%m/%Y %H:%M"),
            "empreinte": s.empreinte,
        })
    return out


@router.post("/{evaluation_id}/signer", status_code=201)
def signer(evaluation_id: int, db: Session = Depends(get_db),
           user: Salarie = Depends(get_current_user)):
    """Appose la signature électronique de l'étape clôturée : l'empreinte
    SHA-256 engage (n° fiche | étape | signataire | horodatage)."""
    ev = db.query(Evaluation).get(evaluation_id)
    if not ev:
        raise HTTPException(404, "Fiche introuvable.")
    role = mon_role(db, ev, user)
    if role in (None, "ADMIN"):
        raise HTTPException(403, "Seuls N, N+1 ou N+2 peuvent signer cette fiche.")
    ok = (
        (role == "N" and ev.statut_n == "Clôturée")
        or (role == "N+1" and ev.statut_n1 == "Clôturée")
        or (role == "N+2" and ev.statut_global == "Approuvé")
    )
    if not ok:
        raise HTTPException(422, f"Votre étape {role} n'est pas encore clôturée : signature impossible.")
    if any(s.etape == role for s in _signatures(db, evaluation_id)):
        raise HTTPException(409, f"Étape {role} déjà signée.")
    emp = hashlib.sha256(
        f"{ev.numero}|{role}|{user.matricule}|{datetime.now().isoformat()}".encode()
    ).hexdigest()
    db.add(Signature(evaluation_id=evaluation_id, etape=role,
                     auteur_id=user.id, empreinte=emp))
    db.commit()
    return {"detail": f"Étape {role} signée électroniquement.", "empreinte": emp}
