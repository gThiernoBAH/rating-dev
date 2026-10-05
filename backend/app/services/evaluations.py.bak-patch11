# 2026-10-02 — règles métier de la fiche d'évaluation : séquencement strict N -> N+1 -> N+2,
# cadenas, commentaire obligatoire, permissions par rôle (§6, §12). Cœur du système.
from sqlalchemy.orm import Session

from app.models.rating import (
    Approbation, Campagne, EmploiProfil, Evaluation, EvaluationLigne,
    ProfilCritere, Salarie,
)

MSG_AUTO_ENCOURS = "Auto-Évaluation en cours. Impossible de procéder à l'Évaluation N+1."
MSG_EVAL_ENCOURS = "Évaluation en cours. Impossible de procéder à l'Approbation N+2."


def campagne_ouverte(db: Session, evaluation: Evaluation) -> bool:
    c = db.query(Campagne).get(evaluation.campagne_id)
    return c is not None and c.statut == "Ouverte"


def mon_role(db: Session, evaluation: Evaluation, user: Salarie) -> str | None:
    """Retourne 'N', 'N+1', 'N+2', 'ADMIN' ou None selon les liens hiérarchiques (§5)."""
    if user.is_admin:
        return "ADMIN"
    if evaluation.salarie_id == user.id:
        return "N"
    salarie = db.query(Salarie).get(evaluation.salarie_id)
    if salarie and salarie.n1_id == user.id:
        return "N+1"
    if salarie and salarie.n1:
        if salarie.n1.n1_id == user.id:
            return "N+2"
    return None


def _toutes_lignes(db: Session, evaluation_id: int, etape: str) -> list[EvaluationLigne]:
    return (
        db.query(EvaluationLigne)
        .filter(EvaluationLigne.evaluation_id == evaluation_id,
                EvaluationLigne.etape == etape)
        .all()
    )


def criteres_attendus(db: Session, evaluation: Evaluation) -> list[tuple[int, int]]:
    """(profil_id, critere_id) attendus = critères des profils attribués à l'emploi du salarié."""
    salarie = db.query(Salarie).get(evaluation.salarie_id)
    if not salarie or not salarie.emploi_id:
        return []
    profils_ids = [
        ep.profil_id
        for ep in db.query(EmploiProfil)
        .filter(EmploiProfil.emploi_id == salarie.emploi_id)
        .order_by(EmploiProfil.ordre)
        .all()
    ]
    attendus = []
    for pid in profils_ids:
        for pc in db.query(ProfilCritere).filter(ProfilCritere.profil_id == pid).all():
            attendus.append((pid, pc.critere_id))
    return attendus


def verif_completude(db: Session, evaluation: Evaluation, etape: str) -> list[str]:
    """Clôture refusée si un critère attendu est vide ou sans commentaire (§6.4)."""
    attendus = criteres_attendus(db, evaluation)
    remplies = {
        (l.profil_id, l.critere_id): l
        for l in _toutes_lignes(db, evaluation.id, etape)
        if l.critere_detail_id is not None
    }
    manquants = []
    for pid, cid in attendus:
        l = remplies.get((pid, cid))
        if not l or not l.commentaire or not l.commentaire.strip():
            manquants.append(f"profil#{pid}/critere#{cid}")
    return manquants


def peut_saisir(db: Session, evaluation: Evaluation, etape: str, user: Salarie) -> tuple[bool, str]:
    """Garde de saisie : campagne ouverte + séquencement strict + étape en cours."""
    if not campagne_ouverte(db, evaluation):
        return False, "Campagne clôturée : plus aucune modification possible."
    if etape == "N":
        if evaluation.statut_n != "En cours":
            return False, "Étape déjà clôturée (cadenas)."
        return True, ""
    if etape == "N+1":
        if evaluation.statut_n != "Clôturée":
            return False, MSG_AUTO_ENCOURS          # blocage systématique §6.5
        if evaluation.statut_n1 != "En cours":
            return False, "Étape déjà clôturée (cadenas)."
        return True, ""
    return False, "Étape inconnue."


def peut_approuver(db: Session, evaluation: Evaluation, user: Salarie) -> tuple[bool, str]:
    if not campagne_ouverte(db, evaluation):
        return False, "Campagne clôturée."
    if evaluation.statut_n1 != "Clôturée":
        return False, MSG_EVAL_ENCOURS              # blocage systématique §6.5
    return True, ""


def cloturer(db: Session, evaluation: Evaluation, etape: str) -> None:
    if etape == "N":
        evaluation.statut_n = "Clôturée"
    elif etape == "N+1":
        evaluation.statut_n1 = "Clôturée"


def approuver(db: Session, evaluation: Evaluation, decision: str,
              observation: str | None, auteur_id: int) -> None:
    evaluation.statut_n2 = "Clôturée"
    evaluation.statut_global = "Approuvé"
    db.add(Approbation(
        evaluation_id=evaluation.id, decision=decision,
        observation=observation, auteur_id=auteur_id,
    ))
