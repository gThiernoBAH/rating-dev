# PATCH 12 — benchmark inter-sections (Admin) : agrégats par section,
# TOUTES les sections affichées (plus d'anonymisation < 5 fiches).
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import require_admin
from app.models.rating import Evaluation, Salarie, Section

router = APIRouter(prefix="/api/bench", tags=["Benchmark"])


@router.get("/sections")
def sections(db: Session = Depends(get_db),
             admin: Salarie = Depends(require_admin)):
    agg: dict = {}
    evals = db.query(Evaluation).all()
    for e in evals:
        s = db.query(Salarie).get(e.salarie_id)
        if not s or not s.section_id:
            continue
        sect = db.query(Section).get(s.section_id)
        lib = sect.libelle if sect else "?"
        a = agg.setdefault(lib, {"nb": 0, "n": 0, "n1": 0, "app": 0})
        a["nb"] += 1
        if e.statut_n == "Clôturée":
            a["n"] += 1
        if e.statut_n1 == "Clôturée":
            a["n1"] += 1
        if e.statut_global == "Approuvé":
            a["app"] += 1
    return [{
        "section": lib, "nb_fiches": a["nb"],
        "pct_n": round(100 * a["n"] / a["nb"]),
        "pct_n1": round(100 * a["n1"] / a["nb"]),
        "pct_approuvees": round(100 * a["app"] / a["nb"]),
    } for lib, a in sorted(agg.items(), key=lambda kv: -kv[1]["nb"])]
