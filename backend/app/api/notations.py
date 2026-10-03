# 2026-10-02 — fiche Notations (§7) : NOTE1/NOTE2, VALEUR1/VALEUR2, RATE (étoiles),
# commentaires côte à côte, totaux par profil, note globale /5 par étape,
# appréciation par paliers paramétrables, badge divergence N vs N+1.
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.rating import (
    Approbation, Critere, CritereDetail, EmploiProfil, Evaluation,
    EvaluationLigne, Profil, ProfilCritere, Salarie,
)
from app.schemas.evaluation import (
    FicheDetail, NotationFiche, NotationLigne, NotationProfil,
)
from app.services.evaluations import mon_role
from app.services.notation import calc_note_globale, calc_rate, calc_valeur, est_divergente
from app.services.params import appreciation

router = APIRouter(prefix="/api/notations", tags=["Notations"])


@router.get("/{evaluation_id}", response_model=NotationFiche)
def notation(evaluation_id: int, db: Session = Depends(get_db),
             user: Salarie = Depends(get_current_user)):
    e = db.query(Evaluation).get(evaluation_id)
    if not e:
        raise HTTPException(404, "Fiche introuvable.")
    role = mon_role(db, e, user)
    if role is None:
        raise HTTPException(403, "Accès refusé.")

    from app.api.evaluations import _entete
    from app.services.params import appreciation, get_param
    ent = _entete(db, e)
    s = db.query(Salarie).get(e.salarie_id)
    seuil = float(get_param(db, "seuil_divergence", "2"))

    profils_ids = [
        ep.profil_id for ep in
        db.query(EmploiProfil).filter(EmploiProfil.emploi_id == s.emploi_id)
        .order_by(EmploiProfil.ordre).all()
    ] if s.emploi_id else []

    lignes = db.query(EvaluationLigne).filter(
        EvaluationLigne.evaluation_id == e.id).all()
    par_cle = {(l.profil_id, l.critere_id, l.etape): l for l in lignes}

    profils_out, all1, all2 = [], [], []
    for pid in profils_ids:
        p = db.query(Profil).get(pid)
        pcs = db.query(ProfilCritere).filter(ProfilCritere.profil_id == pid) \
            .order_by(ProfilCritere.ordre).all()
        lignes_out, l1, l2 = [], [], []
        total_coeff = 0.0
        for pc in pcs:
            c = db.query(Critere).get(pc.critere_id)
            ln, ln1 = par_cle.get((pid, pc.critere_id, "N")), par_cle.get((pid, pc.critere_id, "N+1"))
            d1 = db.query(CritereDetail).get(ln.critere_detail_id) if ln and ln.critere_detail_id else None
            d2 = db.query(CritereDetail).get(ln1.critere_detail_id) if ln1 and ln1.critere_detail_id else None
            n1, n2 = float(d1.valeur) if d1 else None, float(d2.valeur) if d2 else None
            coeff = float(pc.coefficient)
            total_coeff += coeff
            if n1 is not None:
                l1.append((n1, coeff))
            if n2 is not None:
                l2.append((n2, coeff))
            lignes_out.append(NotationLigne(
                profil_libelle=p.libelle if p else "",
                critere_libelle=c.libelle if c else "",
                coefficient=coeff,
                note1=n1, note2=n2,
                valeur1=calc_valeur(n1, coeff) if n1 is not None else None,
                valeur2=calc_valeur(n2, coeff) if n2 is not None else None,
                commentaire_n=ln.commentaire if ln else None,
                commentaire_n1=ln1.commentaire if ln1 else None,
                rate1=calc_rate(n1), rate2=calc_rate(n2),
                divergence=est_divergente(n1, n2, seuil),
            ))
        all1 += l1; all2 += l2
        profils_out.append(NotationProfil(
            profil_libelle=p.libelle if p else "",
            lignes=lignes_out, total_coeff=round(total_coeff, 2),
            total_valeur1=None, total_valeur2=None,
            note_globale1=calc_note_globale(l1),
            note_globale2=calc_note_globale(l2),
        ))
        # totaux par profil (Somme VALEUR)
        profils_out[-1].total_valeur1 = round(sum(n * c for n, c in l1), 2) if l1 else None
        profils_out[-1].total_valeur2 = round(sum(n * c for n, c in l2), 2) if l2 else None

    g1, g2 = calc_note_globale(all1), calc_note_globale(all2)
    approb = db.query(Approbation).filter(
        Approbation.evaluation_id == e.id).first()
    return NotationFiche(
        entete=ent, profils=profils_out,
        note_globale_n=g1, note_globale_n1=g2,
        appreciation_n=appreciation(db, g1),
        appreciation_n1=appreciation(db, g2),
        approbation={"decision": approb.decision, "observation": approb.observation}
        if approb else None,
    )
