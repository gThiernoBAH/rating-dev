# 2026-10-02 — fiches d'évaluation : tableau M3 (sections N/N+1/N+2 selon le rôle,
# blocages par statuts), fiche M4 (onglets profils, grille grisée par rôle),
# saisie QCM (libellé descriptif affiché, note cachée), cadenas, approbation N+2.
# L'Admin : lecture à tout moment, AUCUNE route d'écriture (§12).
from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user, require_admin
from app.models.rating import (
    Approbation, Critere, CritereDetail, EmploiProfil, Evaluation,
    EvaluationLigne, Poste, Profil, ProfilCritere, Salarie,
)
from app.schemas.common import MessageResponse
from app.schemas.evaluation import (
    ApprobationIn, ClotureIn, CommentaireGlobalIn, FicheDetail, FicheEntete,
    LigneFiche, QcmIn,
)
from app.services.audit import log_action
from app.services.evaluations import (
    approuver, cloturer, campagne_ouverte, mon_role, peut_approuver,
    peut_saisir, verif_completude,
)
from app.services.hierarchie import collaborateurs_directs, collaborateurs_indirects

router = APIRouter(prefix="/api/evaluations", tags=["Évaluations"])


def _entete(db: Session, e: Evaluation) -> FicheEntete:
    from app.models.rating import Emploi, Departement, Section, Categorie
    s = db.query(Salarie).get(e.salarie_id)
    emploi_lib = poste_lib = dept_lib = sect_lib = cat_lib = None
    anciennete = None
    if s:
        if s.emploi_id:
            em = db.query(Emploi).get(s.emploi_id)
            emploi_lib = em.libelle if em else None
        if s.poste_id:
            po = db.query(Poste).get(s.poste_id)
            poste_lib = po.libelle if po else None
        from app.models.rating import Departement, Section, Categorie
        if s.departement_id:
            d = db.query(Departement).get(s.departement_id)
            dept_lib = d.libelle if d else None
        if s.section_id:
            sc = db.query(Section).get(s.section_id)
            sect_lib = sc.libelle if sc else None
        if s.categorie_id:
            ca = db.query(Categorie).get(s.categorie_id)
            cat_lib = ca.libelle if ca else None
        if s.date_embauche:
            anciennete = (date.today() - s.date_embauche).days // 365
    n1 = db.query(Salarie).get(s.n1_id) if s and s.n1_id else None
    n1_poste = None
    if n1 and n1.poste_id:
        po = db.query(Poste).get(n1.poste_id)
        n1_poste = po.libelle if po else None
    return FicheEntete(
        id=e.id, numero=e.numero, matricule=s.matricule if s else "",
        nom=s.full_name if s else "", emploi=emploi_lib, poste=poste_lib,
        departement=dept_lib, section=sect_lib, categorie=cat_lib,
        anciennete_annees=anciennete,
        n1_nom=n1.full_name if n1 else None, n1_poste=n1_poste,
        date_evaluation=e.date_evaluation,
        statut_n=e.statut_n, statut_n1=e.statut_n1, statut_n2=e.statut_n2,
        statut_global=e.statut_global, commentaire_global=e.commentaire_global,
    )


@router.get("", response_model=list[dict])
def tableau_evaluations(campagne_id: int, db: Session = Depends(get_db),
                        user: Salarie = Depends(get_current_user)):
    """Tableau M3 : 3 sections selon le rôle — mes fiches (N), mes collaborateurs
    directs (N+1), mes collaborateurs indirects (N+2). Admin : tout, en lecture."""
    qs = db.query(Evaluation).filter(Evaluation.campagne_id == campagne_id)
    fiches = qs.all()

    if user.is_admin:
        ids = None                       # tout
    else:
        directs = {s.id for s in collaborateurs_directs(db, user.id)}
        indirects = {s.id for s in collaborateurs_indirects(db, user.id)}
        ids = {user.id} | directs | indirects

    out = []
    for e in fiches:
        if ids is not None and e.salarie_id not in ids:
            continue
        ent = _entete(db, e)
        s = db.query(Salarie).get(e.salarie_id)
        section = ent.section or ""
        if user.is_admin:
            role = "ADMIN"
        elif e.salarie_id == user.id:
            role = "N"
        elif s and s.n1_id == user.id:
            role = "N+1"
        else:
            role = "N+2"
        out.append({
            "id": e.id, "numero": e.numero, "matricule": ent.matricule,
            "salaries": ent.nom, "section": section,
            "date_evaluation": str(e.date_evaluation or ""),
            "statut_n": e.statut_n, "statut_n1": e.statut_n1,
            "statut_n2": e.statut_n2, "statut_global": e.statut_global,
            "role": role,
        })
    return out


@router.get("/{evaluation_id}", response_model=FicheDetail)
def fiche(evaluation_id: int, db: Session = Depends(get_db),
          user: Salarie = Depends(get_current_user)):
    """Fiche M4 : onglets = profils de l'emploi, grille à 6 colonnes.
    La note est cachée : seuls les libellés descriptifs choisis sont renvoyés."""
    e = db.query(Evaluation).get(evaluation_id)
    if not e:
        raise HTTPException(404, "Fiche introuvable.")
    role = mon_role(db, e, user)
    if role is None:
        raise HTTPException(403, "Vous n'avez pas accès à cette fiche.")

    ent = _entete(db, e)
    s = db.query(Salarie).get(e.salarie_id)

    # profils attribués à l'emploi (§6.2), ordonnés
    profils_ids = [
        ep.profil_id for ep in
        db.query(EmploiProfil).filter(EmploiProfil.emploi_id == s.emploi_id)
        .order_by(EmploiProfil.ordre).all()
    ] if s.emploi_id else []

    lignes = db.query(EvaluationLigne).filter(
        EvaluationLigne.evaluation_id == e.id).all()
    par_cle = {(l.profil_id, l.critere_id, l.etape): l for l in lignes}

    fiche_lignes = []
    for pid in profils_ids:
        p = db.query(Profil).get(pid)
        pcs = db.query(ProfilCritere).filter(ProfilCritere.profil_id == pid) \
            .order_by(ProfilCritere.ordre).all()
        for pc in pcs:
            c = db.query(Critere).get(pc.critere_id)
            details = db.query(CritereDetail) \
                .filter(CritereDetail.critere_id == pc.critere_id) \
                .order_by(CritereDetail.ordre).all()
            ln = par_cle.get((pid, pc.critere_id, "N"))
            ln1 = par_cle.get((pid, pc.critere_id, "N+1"))
            auto_det = db.query(CritereDetail).get(ln.critere_detail_id) if ln and ln.critere_detail_id else None
            eval_det = db.query(CritereDetail).get(ln1.critere_detail_id) if ln1 and ln1.critere_detail_id else None
            fiche_lignes.append(LigneFiche(
                profil_id=pid, profil_libelle=p.libelle if p else "",
                critere_id=pc.critere_id, critere_libelle=c.libelle if c else "",
                ordre=pc.ordre, coefficient=float(pc.coefficient),
                auto_libelle=auto_det.libelle_descriptif if auto_det else None,
                commentaire_n=ln.commentaire if ln else None,
                eval_libelle=eval_det.libelle_descriptif if eval_det else None,
                commentaire_n1=ln1.commentaire if ln1 else None,
                details=[{"id": d.id, "libelle": d.libelle_descriptif}
                         for d in details],
            ))

    mon_etape = role if role in ("N", "N+1", "N+2") else "ADMIN"
    return FicheDetail(entete=ent, profils=fiche_lignes, mon_etape=mon_etape)


@router.post("/{evaluation_id}/qcm", response_model=MessageResponse)
def saisir_qcm(evaluation_id: int, p: QcmIn, db: Session = Depends(get_db),
               user: Salarie = Depends(get_current_user)):
    """Saisie QCM (§6.3) : coche un libellé descriptif, commentaire obligatoire,
    la cellule affiche le libellé (la note reste cachée). Admin : refus (lecture seule)."""
    e = db.query(Evaluation).get(evaluation_id)
    if not e:
        raise HTTPException(404, "Fiche introuvable.")
    role = mon_role(db, e, user)
    if role == "ADMIN":
        raise HTTPException(403, "L'Admin ne modifie jamais les fiches.")
    if (p.etape == "N" and role != "N") or (p.etape == "N+1" and role != "N+1"):
        raise HTTPException(403, "Ce rôle ne peut pas saisir cette étape.")

    ok, msg = peut_saisir(db, e, p.etape, user)
    if not ok:
        raise HTTPException(409, msg)      # messages de blocage §6.5

    detail = db.query(CritereDetail).get(p.critere_detail_id)
    if not detail or detail.critere_id != p.critere_id:
        raise HTTPException(422, "Détail de critère invalide pour ce critère.")

    if p.etape == "N+1":
        ligne_n = db.query(EvaluationLigne).filter(
            EvaluationLigne.evaluation_id == evaluation_id,
            EvaluationLigne.profil_id == p.profil_id,
            EvaluationLigne.critere_id == p.critere_id,
            EvaluationLigne.etape == "N",
        ).first()
        if ligne_n and ligne_n.commentaire and \
           ligne_n.commentaire.strip().lower() == p.commentaire.strip().lower():
            raise HTTPException(422, "Rejeté : votre commentaire est identique à celui du salarié (copier-coller interdit). Reformulez votre appréciation.")

    ligne = db.query(EvaluationLigne).filter(
        EvaluationLigne.evaluation_id == evaluation_id,
        EvaluationLigne.profil_id == p.profil_id,
        EvaluationLigne.critere_id == p.critere_id,
        EvaluationLigne.etape == p.etape,
    ).first()
    avant = None
    if ligne:
        avant = {"critere_detail_id": ligne.critere_detail_id,
                 "commentaire": ligne.commentaire}
        ligne.critere_detail_id = p.critere_detail_id
        ligne.commentaire = p.commentaire.strip()
    else:
        ligne = EvaluationLigne(
            evaluation_id=evaluation_id, profil_id=p.profil_id,
            critere_id=p.critere_id, etape=p.etape,
            critere_detail_id=p.critere_detail_id,
            commentaire=p.commentaire.strip(),
        )
        db.add(ligne)

    log_action(db, auteur_id=user.id, action="SAISIE_QCM",
               table_cible="evaluation_lignes", enregistrement_id=evaluation_id,
               avant=avant, apres={"critere_detail_id": p.critere_detail_id,
                                   "commentaire": p.commentaire.strip()})
    db.commit()
    return MessageResponse(detail="Réponse enregistrée. Cellule remplie avec la description choisie.")


@router.post("/{evaluation_id}/cloturer", response_model=MessageResponse)
def cloturer_etape(evaluation_id: int, p: ClotureIn, db: Session = Depends(get_db),
                   user: Salarie = Depends(get_current_user)):
    """Cadenas (§6.4) : clôture définitive et irréversible de SON étape.
    Refus si un critère d'un profil est vide ou sans commentaire."""
    e = db.query(Evaluation).get(evaluation_id)
    if not e:
        raise HTTPException(404, "Fiche introuvable.")
    role = mon_role(db, e, user)
    if role == "ADMIN":
        raise HTTPException(403, "L'Admin ne clôture jamais une étape.")
    if (p.etape == "N" and role != "N") or (p.etape == "N+1" and role != "N+1"):
        raise HTTPException(403, "Vous ne pouvez clôturer que votre étape.")

    ok, msg = peut_saisir(db, e, p.etape, user)
    if not ok:
        raise HTTPException(409, msg)

    manquants = verif_completude(db, e, p.etape)
    if manquants:
        raise HTTPException(
            409,
            f"Clôture refusée : {len(manquants)} critère(s) vide(s) ou sans commentaire.",
        )

    cloturer(db, e, p.etape)
    log_action(db, auteur_id=user.id, action=f"CLOTURE_{p.etape}",
               table_cible="evaluations", enregistrement_id=e.id)
    db.commit()
    return MessageResponse(detail="Étape clôturée (cadenas). Action définitive.")


@router.post("/{evaluation_id}/approuver", response_model=MessageResponse)
def approuver_etape(evaluation_id: int, p: ApprobationIn, db: Session = Depends(get_db),
                    user: Salarie = Depends(get_current_user)):
    """Approbation N+2 (§6.5) : Approuvé / Approuvé avec réserves + observation.
    Jamais de re-notation. Bloquée tant que N+1 n'a pas clôturé."""
    e = db.query(Evaluation).get(evaluation_id)
    if not e:
        raise HTTPException(404, "Fiche introuvable.")
    role = mon_role(db, e, user)
    if role != "N+2":
        raise HTTPException(403, "Seul le N+2 peut approuver.")

    ok, msg = peut_approuver(db, e, user)
    if not ok:
        raise HTTPException(409, msg)
    if p.decision == "Approuvé avec réserves" and not p.observation:
        raise HTTPException(422, "Observation obligatoire pour une approbation avec réserves.")

    approuver(db, e, p.decision, p.observation, user.id)
    log_action(db, auteur_id=user.id, action="APPROBATION",
               table_cible="evaluations", enregistrement_id=e.id,
               apres={"decision": p.decision, "observation": p.observation})
    db.commit()
    return MessageResponse(detail="Approbation enregistrée. Fiche Approuvée.")


@router.post("/{evaluation_id}/commentaire-global", response_model=MessageResponse)
def commentaire_global(evaluation_id: int, p: CommentaireGlobalIn,
                       db: Session = Depends(get_db),
                       user: Salarie = Depends(get_current_user)):
    e = db.query(Evaluation).get(evaluation_id)
    if not e:
        raise HTTPException(404, "Fiche introuvable.")
    role = mon_role(db, e, user)
    if role == "ADMIN" or role is None:
        raise HTTPException(403, "Action non permise pour votre rôle.")
    e.commentaire_global = p.commentaire_global.strip()
    db.commit()
    return MessageResponse(detail="Commentaire global enregistré.")


@router.post("/{evaluation_id}/deverrouiller", response_model=MessageResponse)
def deverrouiller(evaluation_id: int, etape: str, justification: str,
                  db: Session = Depends(get_db),
                  admin: Salarie = Depends(require_admin)):
    """Déverrouillage : Admin SEUL, justification obligatoire journalisée (§6.4)."""
    e = db.query(Evaluation).get(evaluation_id)
    if not e:
        raise HTTPException(404, "Fiche introuvable.")
    if etape not in ("N", "N+1"):
        raise HTTPException(422, "etape : 'N' ou 'N+1'.")
    if not justification.strip():
        raise HTTPException(422, "Justification obligatoire.")
    if etape == "N":
        e.statut_n = "En cours"
    else:
        e.statut_n1 = "En cours"
    log_action(db, auteur_id=admin.id, action=f"DEVERROUILLAGE_{etape}",
               table_cible="evaluations", enregistrement_id=e.id,
               justification=justification.strip())
    db.commit()
    return MessageResponse(detail="Étape déverrouillée. Justification journalisée.")
