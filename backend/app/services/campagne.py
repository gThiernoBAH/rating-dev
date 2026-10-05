# 2026-10-05 PATCH 12 — génération des fiches : idempotente, par famille,
# cutoff d'ancienneté, CASCADE des référentiels actifs (site/dépt/section/
# emploi/catégorie/poste), hors-évaluation, pré-remplissage des critères
# « A REMPLIR » (editable) avec les objectifs de la campagne précédente.
from datetime import date

from sqlalchemy.orm import Session

from app.models.rating import (
    Critere, Emploi, EmploiProfil, Evaluation, EvaluationCritere, Objectif,
    ProfilCritere, Salarie,
)
from app.schemas.campagne import GenerationReport
from app.services.params import get_param


def _cutoff_date(db: Session, date_cloture: date | None) -> date | None:
    # PATCH 9 — 6 mois d'ancienneté minimum pour être évalué
    mois = int(get_param(db, "cutoff_anciennete_mois", "6"))
    if not date_cloture:
        return None
    from dateutil.relativedelta import relativedelta
    return date_cloture - relativedelta(months=mois)


def _chaine_active(db: Session, s) -> bool:
    """PATCH 12 — toute la chaîne de rattachement doit être active."""
    from app.models.rating import Categorie, Departement, Poste, Section, Site
    for ref_id, model in [(s.site_id, Site), (s.departement_id, Departement),
                          (s.section_id, Section), (s.emploi_id, Emploi),
                          (s.categorie_id, Categorie), (s.poste_id, Poste)]:
        if ref_id is None:
            continue
        o = db.query(model).get(ref_id)
        if o is not None and not getattr(o, "actif", True):
            return False
    return True


def _prefill_objectifs(db: Session, campagne, evaluation, salarie) -> int:
    """PATCH 12 — les objectifs (écran OBJECTIFS) de la campagne N-1 deviennent
    les libellés des critères éditables (« A REMPLIR ») de la fiche N."""
    if not salarie.emploi_id:
        return 0
    profils_ids = [ep.profil_id for ep in db.query(EmploiProfil)
                   .filter(EmploiProfil.emploi_id == salarie.emploi_id)
                   .order_by(EmploiProfil.ordre).all()]
    editables = []
    for pid in profils_ids:
        for pc in db.query(ProfilCritere).filter(ProfilCritere.profil_id == pid).all():
            c = db.query(Critere).get(pc.critere_id)
            if c and c.editable:
                editables.append(pc.critere_id)
    if not editables:
        return 0
    objs = db.query(Objectif).filter(
        Objectif.salarie_id == salarie.id,
        Objectif.annee < campagne.exercice,
    ).order_by(Objectif.annee.desc(), Objectif.trimestre.desc(), Objectif.id).all()
    titres = [o.titre for o in objs][:len(editables)]
    for cid, t in zip(editables, titres):
        db.add(EvaluationCritere(evaluation_id=evaluation.id,
                                 critere_id=cid, libelle=t))
    return len(titres)


def generer_fiches(db: Session, campagne, familles: list[int],
                   rattrapage: bool = False) -> GenerationReport:
    rap = GenerationReport()
    cutoff = _cutoff_date(db, campagne.date_cloture)

    deja = {e.salarie_id
            for e in db.query(Evaluation)
            .filter(Evaluation.campagne_id == campagne.id).all()}
    seq = len(deja)

    emplois_familles = {em.id: em.famille
                        for em in db.query(Emploi).filter(Emploi.famille.in_(familles)).all()}

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
        if not _chaine_active(db, s):          # PATCH 12 — cascade actifs
            rap.exclus_inactifs += 1
            continue
        if not s.n1_id:
            rap.sans_n1.append(s.matricule)
            continue
        if cutoff and s.date_embauche and s.date_embauche >= cutoff:
            rap.cutoff_exclus += 1
            continue
        if s.id in deja:
            rap.deja_existantes += 1
            continue

        seq += 1
        numero = f"{campagne.exercice % 100}{seq:06d}"
        ev = Evaluation(
            campagne_id=campagne.id, salarie_id=s.id, numero=numero,
            date_evaluation=campagne.date_ouverture,
        )
        db.add(ev)
        db.flush()
        rap.objectifs_prefilles += _prefill_objectifs(db, campagne, ev, s)  # PATCH 12
        rap.creees += 1

    db.flush()
    return rap
