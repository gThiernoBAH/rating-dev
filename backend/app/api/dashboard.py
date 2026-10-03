# 2026-10-02 — tableaux de bord d'avancement (§10) : Admin + N+1. Exports Excel prévus.
from fastapi import APIRouter, Depends
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.rating import Campagne, Evaluation, Salarie, Section
from app.services.hierarchie import collaborateurs_directs

router = APIRouter(prefix="/api/dashboard", tags=["Tableaux de bord"])


@router.get("/avancement")
def avancement(campagne_id: int, db: Session = Depends(get_db),
               user: Salarie = Depends(get_current_user)):
    """% N / N+1 / N+2 par section, retardataires, anomalies (sans N+1, hors éval)."""
    if not user.is_admin and not collaborateurs_directs(db, user.id):
        return {"erreur": "Réservé aux Admin et N+1."}

    fiches = db.query(Evaluation).filter(Evaluation.campagne_id == campagne_id).all()
    if user.is_admin:
        perimetre = fiches
    else:  # N+1 : son périmètre uniquement
        ids = {s.id for s in collaborateurs_directs(db, user.id)} | {user.id}
        perimetre = [f for f in fiches if f.salarie_id in ids]

    par_section: dict[str, dict] = {}
    retardataires = []
    for f in perimetre:
        s = db.query(Salarie).get(f.salarie_id)
        sec = db.query(Section).get(s.section_id).libelle if s and s.section_id else "Sans section"
        d = par_section.setdefault(sec, {"total": 0, "n": 0, "n1": 0, "n2": 0})
        d["total"] += 1
        if f.statut_n == "Clôturée":
            d["n"] += 1
        elif s.id != user.id and not user.is_admin:
            retardataires.append({"matricule": s.matricule, "nom": s.full_name})
        if f.statut_n1 == "Clôturée":
            d["n1"] += 1
        if f.statut_n2 == "Clôturée":
            d["n2"] += 1

    result = []
    for sec, d in sorted(par_section.items()):
        t = d["total"] or 1
        result.append({
            "section": sec, "total": d["total"],
            "pct_n": round(100 * d["n"] / t, 1),
            "pct_n1": round(100 * d["n1"] / t, 1),
            "pct_n2": round(100 * d["n2"] / t, 1),
        })

    sans_n1 = db.query(Salarie).filter(
        Salarie.n1_id.is_(None), Salarie.is_active.is_(True),
        Salarie.is_admin.is_(False)).count()
    hors_eval = db.query(Salarie).filter(
        Salarie.hors_evaluation.is_(True)).count()

    camp = db.query(Campagne).get(campagne_id)
    return {"campagne": camp.nom if camp else "", "sections": result,
            "retardataires": retardataires,
            "anomalies": {"sans_n1": sans_n1, "hors_evaluation": hors_eval}}
