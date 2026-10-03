# 2026-10-02 — génération automatique des fiches (§4) : idempotente, par famille,
# cutoff d'ancienneté paramétrable, rapport détaillé, salariés sans N+1 signalés.
from datetime import date

from sqlalchemy.orm import Session

from app.models.rating import Emploi, Evaluation, Salarie
from app.schemas.campagne import GenerationReport
from app.services.params import get_param


def _cutoff_date(db: Session, date_cloture: date | None) -> date | None:
    mois = int(get_param(db, "cutoff_anciennete_mois", "3"))
    if not date_cloture:
        return None
    # embauche < cutoff -> embauché depuis < N mois -> non évalué cette campagne
    from dateutil.relativedelta import relativedelta
    return date_cloture - relativedelta(months=mois)


def generer_fiches(db: Session, campagne, familles: list[int], rattrapage: bool = False) -> GenerationReport:
    rap = GenerationReport()
    cutoff = _cutoff_date(db, campagne.date_cloture)

    deja = {
        e.salarie_id
        for e in db.query(Evaluation).filter(Evaluation.campagne_id == campagne.id).all()
    }
    # séquence : le plus grand numéro existant + 1
    seq = len(deja)

    emplois_familles = {
        em.id: em.famille
        for em in db.query(Emploi).filter(Emploi.famille.in_(familles)).all()
    }

    salaries = db.query(Salarie).filter(
        Salarie.is_active.is_(True),
        Salarie.is_admin.is_(False),
    ).all()

    for s in salaries:
        if s.hors_evaluation:
            rap.hors_evaluation += 1
            continue
        if s.emploi_id is None or s.emploi_id not in emplois_familles:
            continue
        if not s.n1_id:
            rap.sans_n1.append(s.matricule)   # signalé, fiche non créée
            continue
        if cutoff and s.date_embauche and s.date_embauche < cutoff:
            rap.cutoff_exclus += 1
            continue
        if s.id in deja:
            rap.deja_existantes += 1
            continue

        seq += 1
        numero = f"{campagne.exercice % 100}{seq:06d}"   # ex. 26000610
        db.add(Evaluation(
            campagne_id=campagne.id, salarie_id=s.id, numero=numero,
            date_evaluation=campagne.date_ouverture,
        ))
        rap.creees += 1

    db.flush()
    return rap
