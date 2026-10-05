# 2026-10-02 — Navigation (§8) : GRAPHE salarié vs moyenne de sa section, RECAP,
# benchmark inter-sections par critère, historique inter-exercices. Consultation seule.
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import case, func   # PATCH 12
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.rating import (
    Campagne, Critere, CritereDetail, Evaluation, EvaluationLigne,
    Profil, ProfilCritere, Salarie, Section,
)
from app.services.evaluations import mon_role
from app.services.hierarchie import collaborateurs_directs, collaborateurs_indirects

router = APIRouter(prefix="/api/navigation", tags=["Navigation"])


def _permis(db, user, salarie_id: int) -> bool:
    if user.is_admin:
        return True
    if salarie_id == user.id:
        return True
    directs = {s.id for s in collaborateurs_directs(db, user.id)}
    indirects = {s.id for s in collaborateurs_indirects(db, user.id)}
    cible = db.query(Salarie).get(salarie_id)
    if cible and cible.n2_id == user.id:
        return True
    return salarie_id in (directs | indirects)


@router.get("/criteres")
def criteres_dispo(db: Session = Depends(get_db),
                   user: Salarie = Depends(get_current_user)):
    """Critères actifs — pour le menu BENCHMARK (accessible à tout salarié)."""
    rows = db.query(Critere).filter(Critere.actif.is_(True)).order_by(Critere.code).all()
    return [{"id": cr.id, "libelle": cr.libelle} for cr in rows]


@router.get("/salaries")
def salaries_selectionnables(db: Session = Depends(get_db),
                             user: Salarie = Depends(get_current_user)):
    """Liste de gauche : matricule – nom (soi-même ou périmètre ; Admin : tout)."""
    if user.is_admin:
        salaries = db.query(Salarie).filter(Salarie.is_active.is_(True),
                                            Salarie.is_admin.is_(False)).all()
    else:
        ids = {user.id} | {s.id for s in collaborateurs_directs(db, user.id)} \
              | {s.id for s in collaborateurs_indirects(db, user.id)}
        salaries = db.query(Salarie).filter(Salarie.id.in_(ids),
                                       Salarie.is_admin.is_(False)).all()
    return [{"id": s.id, "matricule": s.matricule, "nom": s.full_name,
            "section_id": s.section_id} for s in salaries]   # PATCH 12


@router.get("/graphe")
def graphe(salarie_id: int, campagne_id: int, db: Session = Depends(get_db),
           user: Salarie = Depends(get_current_user)):
    """Barres par critère : salarié (bleu) vs moyenne de sa section (orange)."""
    if not _permis(db, user, salarie_id):
        raise HTTPException(403, "Hors de votre périmètre.")
    s = db.query(Salarie).get(salarie_id)
    if not s:
        raise HTTPException(404, "Salarié introuvable.")

    notes_sal = dict(db.query(
        EvaluationLigne.critere_id, func.avg(case(
            (CritereDetail.sens == 2,
             func.coalesce(EvaluationLigne.valeur_choisie, CritereDetail.valeur)
             * 5.0 / CritereDetail.valeur_max),
            else_=func.coalesce(EvaluationLigne.valeur_choisie,
                                 CritereDetail.valeur)))  # PATCH 12 : /5 normalisé
    ).join(Evaluation, Evaluation.id == EvaluationLigne.evaluation_id)
     .join(CritereDetail, CritereDetail.id == EvaluationLigne.critere_detail_id)
     .filter(Evaluation.campagne_id == campagne_id,
             Evaluation.salarie_id == salarie_id,
             EvaluationLigne.etape == "N+1")
     .group_by(EvaluationLigne.critere_id).all())

    q = (
        db.query(EvaluationLigne.critere_id, func.avg(case(
            (CritereDetail.sens == 2,
             func.coalesce(EvaluationLigne.valeur_choisie, CritereDetail.valeur)
             * 5.0 / CritereDetail.valeur_max),
            else_=func.coalesce(EvaluationLigne.valeur_choisie,
                                 CritereDetail.valeur))))  # PATCH 12 : /5 normalisé
        .join(Evaluation, Evaluation.id == EvaluationLigne.evaluation_id)
        .join(Salarie, Salarie.id == Evaluation.salarie_id)
        .join(CritereDetail, CritereDetail.id == EvaluationLigne.critere_detail_id)
        .filter(Evaluation.campagne_id == campagne_id,
                EvaluationLigne.etape == "N+1",
                Salarie.section_id == s.section_id)
        .group_by(EvaluationLigne.critere_id)
    )
    notes_sec = dict(q.all())

    criteres = db.query(Critere).order_by(Critere.code).all()
    return [{
        "critere": c.libelle,
        "salarie": round(float(notes_sal.get(c.id) or 0), 2),
        "section": round(float(notes_sec.get(c.id) or 0), 2),
    } for c in criteres if c.id in notes_sal or c.id in notes_sec]


@router.get("/recap")
def recap(salarie_id: int, campagne_id: int, db: Session = Depends(get_db),
          user: Salarie = Depends(get_current_user)):
    """RECAP : valeur sur 5 + RATE, salarié vs section, critère par critère."""
    if not _permis(db, user, salarie_id):
        raise HTTPException(403, "Hors de votre périmètre.")
    s = db.query(Salarie).get(salarie_id)
    base = graphe(salarie_id=salarie_id, campagne_id=campagne_id, db=db, user=user)
    from app.services.notation import calc_rate
    return [{
        "critere": b["critere"],
        "valeur_salarie": b["salarie"], "rate_salarie": calc_rate(b["salarie"] or None),
        "valeur_section": b["section"], "rate_section": calc_rate(b["section"] or None),
    } for b in base]


@router.get("/benchmark")
def benchmark(critere_id: int, campagne_id: int, db: Session = Depends(get_db),
              user: Salarie = Depends(get_current_user)):
    """Benchmark inter-sections (§8) : toutes les sections classées par note
    décroissante sur un critère donné. Analyse Admin/managers."""
    if not user.is_admin:
        d = db.query(Salarie).get(user.id)
        if not (d.is_admin or collaborateurs_directs(db, user.id)):
            raise HTTPException(403, "Réservé aux Admin et managers (N+1).")
    rows = db.query(
        Section.libelle, func.avg(case(
            (CritereDetail.sens == 2,
             func.coalesce(EvaluationLigne.valeur_choisie, CritereDetail.valeur)
             * 5.0 / CritereDetail.valeur_max),
            else_=func.coalesce(EvaluationLigne.valeur_choisie,
                                 CritereDetail.valeur)))  # PATCH 12 : /5 normalisé
    ).join(Salarie, Salarie.section_id == Section.id) \
     .join(Evaluation, Evaluation.salarie_id == Salarie.id) \
     .join(EvaluationLigne, EvaluationLigne.evaluation_id == Evaluation.id) \
     .join(CritereDetail, CritereDetail.id == EvaluationLigne.critere_detail_id) \
     .filter(Evaluation.campagne_id == campagne_id,
             EvaluationLigne.critere_id == critere_id,
             EvaluationLigne.etape == "N+1") \
     .group_by(Section.libelle).all()
    return [{"section": r[0], "moyenne": round(float(r[1]), 2)}
            for r in sorted(rows, key=lambda x: -(x[1] or 0))]


@router.get("/historique")
def historique(salarie_id: int, db: Session = Depends(get_db),
               user: Salarie = Depends(get_current_user)):
    """Évolution d'un salarié campagne à campagne (inter-exercices)."""
    if not _permis(db, user, salarie_id):
        raise HTTPException(403, "Hors de votre périmètre.")
    evals = db.query(Evaluation).filter(Evaluation.salarie_id == salarie_id).all()
    out = []
    from app.api.notations import notation
    for e in sorted(evals, key=lambda x: x.id):
        n = notation(evaluation_id=e.id, db=db, user=user)
        camp = db.query(Campagne).get(e.campagne_id)
        out.append({
            "campagne": f"{camp.nom} {camp.exercice}" if camp else "",
            "note_n1": n.note_globale_n1, "note_n": n.note_globale_n,
            "statut_global": e.statut_global,
        })
    return out


# ================== PATCH 12 : sections du périmètre (filtre NAVIGATION) ==================

@router.get("/sections")
def sections_perimetre(db: Session = Depends(get_db),
                       user: Salarie = Depends(get_current_user)):
    """Sections accessibles dans le périmètre de l'utilisateur (Admin : toutes)."""
    if user.is_admin:
        rows = (db.query(Section)
                .join(Salarie, Salarie.section_id == Section.id)
                .filter(Salarie.is_active.is_(True), Salarie.is_admin.is_(False))
                .distinct().all())
    else:
        ids = {user.id} | {s.id for s in collaborateurs_directs(db, user.id)} \
              | {s.id for s in collaborateurs_indirects(db, user.id)}
        rows = (db.query(Section)
                .join(Salarie, Salarie.section_id == Section.id)
                .filter(Salarie.id.in_(ids)).distinct().all())
    return [{"id": x.id, "libelle": x.libelle} for x in sorted(rows, key=lambda z: z.libelle)]
