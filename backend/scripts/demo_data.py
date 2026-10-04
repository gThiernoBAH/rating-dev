# ============================================================================
# demo_data.py — données de DÉMO pour une campagne EVALPOINT.
#
# Usage (depuis backend/, venv activé) :
#   python scripts/demo_data.py --campagne 4            # remplit les fiches
#   python scripts/demo_data.py --campagne 4 --avancee    # + statuts avancés
#                                                      #   (N clôturé, N+1 partiel)
#   python scripts/demo_data.py --purge                 # purge TOUTES les
#                                                      #   évaluations de démo
#
# Principe : ne touche JAMAIS au référentiel (sites, salariés, emplois,
# profils, critères…). Seules les tables evaluations / evaluation_lignes /
# approbations sont écrites/purgées.
# ============================================================================
import argparse
import random
import sys
from datetime import date

sys.path.insert(0, ".")

from app.core.database import SessionLocal  # noqa: E402
from app.models.rating import (  # noqa: E402
    Approbation, Critere, CritereDetail, EmploiProfil, Evaluation,
    EvaluationLigne, Profil, ProfilCritere, Salarie,
)

COMMENTAIRES_N = [
    "Je maîtrise ce point mais je peux encore progresser.",
    "Aspect bien maîtrisé au quotidien, retours positifs de mon entourage.",
    "Je travaille cet aspect activement cette année.",
    "Ce critère correspond bien à mon quotidien, à l'aise dessus.",
    "Certaines situations me demandent encore de l'expérience.",
]
COMMENTAIRES_N1 = [
    "Salarié régulier sur ce point, conforme aux attentes.",
    "Bonne maîtrise constatée sur les faits de l'année.",
    "À surveiller : des progrès sont attendus au prochain semestre.",
    "Très à l'aise, peut aider à former les nouveaux.",
    "En progression nette depuis le dernier entretien.",
]
OBSERVATIONS = [
    "Dossier complet, évaluation conduite sérieusement.",
    "Quelques réserves mineures sur l'adéquation du poste.",
    "À revoir au prochain cycle pour affiner.",
]


def remplir(db, campagne_id, avancee):
    evs = db.query(Evaluation).filter(Evaluation.campagne_id == campagne_id).all()
    if not evs:
        print("Aucune fiche pour cette campagne — générer les fiches d'abord.")
        return
    n_details = n_commentaires = n_approb = 0
    for e in evs:
        s = db.get(Salarie, e.salarie_id)
        if not s or not s.emploi_id:
            continue
        # lignes = tous les critères des profils de l'emploi
        pcs = (
            db.query(ProfilCritere, EmploiProfil)
            .join(EmploiProfil, EmploiProfil.profil_id == ProfilCritere.profil_id)
            .filter(EmploiProfil.emploi_id == s.emploi_id)
            .all()
        )
        statut_cible = random.random() < (0.85 if avancee else 1.0)
        deja = {
            (l.profil_id, l.critere_id, l.etape)
            for l in db.query(EvaluationLigne)
            .filter(EvaluationLigne.evaluation_id == e.id).all()
        }
        vus = set()
        for pc, ep in pcs:
            if (pc.profil_id, pc.critere_id) in vus:
                continue
            vus.add((pc.profil_id, pc.critere_id))
            # étape N : remplie si le statut le permet
            if e.statut_n == "En cours" and (pc.profil_id, pc.critere_id, "N") not in deja:
                det = (
                    db.query(CritereDetail)
                    .filter(CritereDetail.critere_id == pc.critere_id)
                    .order_by(CritereDetail.ordre)
                    .all()
                )
                if det and random.random() < 0.9:  # 10 % laissées vides
                    db.add(EvaluationLigne(
                        evaluation_id=e.id, profil_id=pc.profil_id,
                        critere_id=pc.critere_id, etape="N",
                        critere_detail_id=random.choice(det).id,
                        commentaire=random.choice(COMMENTAIRES_N),
                    ))
                    n_details += 1
            # étape N+1 : remplie seulement en mode avancé, si l'auto-éval existe
            if avancee and statut_cible and e.statut_n == "Clôturée" and e.statut_n1 == "En cours" \
                    and (pc.profil_id, pc.critere_id, "N+1") not in deja:
                det = (
                    db.query(CritereDetail)
                    .filter(CritereDetail.critere_id == pc.critere_id)
                    .order_by(CritereDetail.ordre)
                    .all()
                )
                if det and random.random() < 0.9:
                    db.add(EvaluationLigne(
                        evaluation_id=e.id, profil_id=pc.profil_id,
                        critere_id=pc.critere_id, etape="N+1",
                        critere_detail_id=random.choice(det).id,
                        commentaire=random.choice(COMMENTAIRES_N1),
                    ))
                    n_commentaires += 1
        # statuts avancés — une étape n'est clôturée QUE si complète
        if avancee:
            attends = vus
            lignes_n = {
                (l.profil_id, l.critere_id)
                for l in db.query(EvaluationLigne)
                .filter(EvaluationLigne.evaluation_id == e.id,
                        EvaluationLigne.etape == "N").all()
            }
            complet_n = attends and attends.issubset(lignes_n)
            if e.statut_n == "En cours" and complet_n and random.random() < 0.7:
                e.statut_n = "Clôturée"
            elif e.statut_n == "Clôturée" and e.statut_n1 == "En cours" and random.random() < 0.5:
                e.statut_n1 = "Clôturée"
            if e.statut_n1 == "Clôturée" and e.statut_global != "Approuvé" and random.random() < 0.4:
                decision = "Approuvé" if random.random() < 0.7 else "Approuvé avec réserves"
                n2 = db.get(Salarie, db.get(Salarie, e.salarie_id).n1_id)
                auteur = n2 or db.query(Salarie).filter(Salarie.is_admin.is_(True)).first()
                db.add(Approbation(
                    evaluation_id=e.id, decision=decision,
                    observation=random.choice(OBSERVATIONS) if decision != "Approuvé" else None,
                    auteur_id=auteur.id if auteur else e.salarie_id,
                ))
                e.statut_global = "Approuvé"
                n_approb += 1
    db.commit()
    print(f"Démo générée : {n_details} lignes N, {n_commentaires} lignes N+1, "
          f"{n_approb} approbations.")


def purge(db):
    n1 = db.query(EvaluationLigne).delete()
    n2 = db.query(Approbation).delete()
    n3 = db.query(Evaluation).delete()
    db.commit()
    print(f"Purge effectuée : {n1} lignes, {n2} approbations, {n3} évaluations supprimées.")
    print("Le référentiel (salariés, emplois, critères…) est intact.")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--campagne", type=int, help="id de la campagne à remplir")
    ap.add_argument("--avancee", action="store_true",
                    help="avance les statuts (N clôturés, N+1 partiels, approbations)")
    ap.add_argument("--purge", action="store_true",
                    help="supprime TOUTES les évaluations (toutes campagnes)")
    args = ap.parse_args()
    db = SessionLocal()
    try:
        if args.purge:
            purge(db)
        elif args.campagne:
            remplir(db, args.campagne, args.avancee)
        else:
            ap.print_help()
    finally:
        db.close()
