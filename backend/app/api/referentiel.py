# 2026-10-02 — CRUD référentiel (M5). Réservé Admin. Suppression bloquée si références.
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import require_admin
from app.models.rating import (
    Categorie, Critere, CritereDetail, Departement, Emploi, EmploiProfil,
    EvaluationLigne, Poste, Profil, ProfilCritere, Salarie, Section, Site,  # PATCH 12
)
from app.schemas.common import MessageResponse
from app.schemas.referentiel import (
    CritereDetailIn, CritereDetailOut, CritereIn, CritereOut, DepartementOut, EmploiOut,
    EmploiProfilsIn, ProfilIn, ProfilOut, SalarieIn, SalarieOut, SectionOut,
    SimpleRef,
)
from app.services.audit import log_action

router = APIRouter(prefix="/api/referentiel", tags=["Référentiel"],
                   dependencies=[Depends(require_admin)])

# --- tables simples : Sites, Departements, Sections, Categories, Postes, Emplois
_SIMPLE = {
    "sites": (Site,), "categories": (Categorie,), "postes": (Poste,),
}


def _crud_simple(table: str, model, out_schema):
    @router.get(f"/{table}", response_model=list[out_schema])
    def list_all(db: Session = Depends(get_db)):
        return db.query(model).order_by(model.code).all()

    @router.post(f"/{table}", response_model=out_schema, status_code=201)
    def create(payload: SimpleRef, db: Session = Depends(get_db)):
        obj = model(code=payload.code, libelle=payload.libelle)
        db.add(obj); db.commit(); db.refresh(obj)
        return obj

    @router.put(f"/{table}/{{item_id}}", response_model=out_schema)
    def update(item_id: int, payload: SimpleRef, db: Session = Depends(get_db)):
        obj = db.query(model).get(item_id)
        if not obj:
            raise HTTPException(404, "Introuvable.")
        avant = {"code": obj.code, "libelle": obj.libelle}
        obj.code, obj.libelle = payload.code, payload.libelle
        db.commit(); db.refresh(obj)
        return obj

    @router.delete(f"/{table}/{{item_id}}", response_model=MessageResponse)
    def delete(item_id: int, db: Session = Depends(get_db)):
        obj = db.query(model).get(item_id)
        if not obj:
            raise HTTPException(404, "Introuvable.")
        db.delete(obj); db.commit()
        return MessageResponse(detail="Supprimé.")


_crud_simple("sites", Site, SimpleRef)
_crud_simple("categories", Categorie, SimpleRef)
_crud_simple("postes", Poste, SimpleRef)


@router.get("/departements", response_model=list[DepartementOut])
def list_departements(db: Session = Depends(get_db)):
    return db.query(Departement).order_by(Departement.code).all()


@router.post("/departements", response_model=DepartementOut, status_code=201)
def create_departement(p: SimpleRef, site_id: int | None = None, db: Session = Depends(get_db)):
    obj = Departement(code=p.code, libelle=p.libelle, site_id=site_id)
    db.add(obj); db.commit(); db.refresh(obj)
    return obj


@router.get("/sections", response_model=list[SectionOut])
def list_sections(db: Session = Depends(get_db)):
    return db.query(Section).order_by(Section.code).all()


@router.post("/sections", response_model=SectionOut, status_code=201)
def create_section(p: SimpleRef, departement_id: int, db: Session = Depends(get_db)):
    obj = Section(code=p.code, libelle=p.libelle, departement_id=departement_id)
    db.add(obj); db.commit(); db.refresh(obj)
    return obj


# --- emplois (+ famille + profils attribués ordonnables)
@router.get("/emplois", response_model=list[EmploiOut])
def list_emplois(db: Session = Depends(get_db)):
    return db.query(Emploi).order_by(Emploi.famille, Emploi.code).all()


@router.post("/emplois", response_model=EmploiOut, status_code=201)
def create_emploi(p: SimpleRef, famille: int, db: Session = Depends(get_db)):
    if famille not in (1, 2, 3):
        raise HTTPException(422, "famille doit valoir 1 (Cadres), 2 (AM) ou 3 (Empl.-Ouvr.).")
    obj = Emploi(code=p.code, libelle=p.libelle, famille=famille)
    db.add(obj); db.commit(); db.refresh(obj)
    return obj


@router.put("/emplois/{emploi_id}/profils", response_model=MessageResponse)
def attribuer_profils(emploi_id: int, p: EmploiProfilsIn, db: Session = Depends(get_db)):
    """Paramétrage fort (§3) : profils↔emplois libres, nombre libre, ordre conservé."""
    db.query(EmploiProfil).filter(EmploiProfil.emploi_id == emploi_id).delete()
    for ordre, pid in enumerate(p.profils):
        db.add(EmploiProfil(emploi_id=emploi_id, profil_id=pid, ordre=ordre))
    db.commit()
    return MessageResponse(detail="Profils attribués.")


# --- critères (+ détails : libellé descriptif + valeur cachée)
@router.get("/criteres", response_model=list[CritereOut])
def list_criteres(db: Session = Depends(get_db)):
    return db.query(Critere).order_by(Critere.code).all()


@router.post("/criteres", response_model=CritereOut, status_code=201)
def create_critere(p: CritereIn, db: Session = Depends(get_db)):
    obj = Critere(code=p.code, libelle=p.libelle, actif=p.actif, editable=p.editable)  # PATCH 12
    db.add(obj); db.flush()
    for d in p.details:
        db.add(CritereDetail(critere_id=obj.id, libelle_descriptif=d.libelle_descriptif,
                             valeur=d.valeur, ordre=d.ordre))
    db.commit(); db.refresh(obj)
    return obj


# --- profils (+ critères + COEFF.)
@router.get("/profils", response_model=list[ProfilOut])
def list_profils(db: Session = Depends(get_db)):
    profils = db.query(Profil).order_by(Profil.code).all()
    resultats = []
    for p in profils:
        pcs = db.query(ProfilCritere).filter(ProfilCritere.profil_id == p.id) \
            .order_by(ProfilCritere.ordre).all()
        resultats.append(ProfilOut(id=p.id, code=p.code, libelle=p.libelle, criteres=[
            {"critere_id": pc.critere_id, "coefficient": float(pc.coefficient),
             "ordre": pc.ordre} for pc in pcs
        ]))
    return resultats


@router.post("/profils", response_model=MessageResponse, status_code=201)
def create_profil(p: ProfilIn, db: Session = Depends(get_db)):
    obj = Profil(code=p.code, libelle=p.libelle)
    db.add(obj); db.flush()
    for c in p.criteres:
        db.add(ProfilCritere(profil_id=obj.id, critere_id=c.critere_id,
                             coefficient=c.coefficient, ordre=c.ordre))
    db.commit()
    return MessageResponse(detail=f"Profil {obj.code} créé.")


# --- salaries (rattachements, N+1, hors évaluation, email)
@router.get("/salaries", response_model=list[SalarieOut])
def list_salaries(db: Session = Depends(get_db)):
    salaries = db.query(Salarie).order_by(Salarie.is_admin.desc(), Salarie.matricule)  # PATCH 12 : Admins en tête.all()
    out = []
    for s in salaries:
        n1 = db.query(Salarie).get(s.n1_id) if s.n1_id else None
        n2 = db.query(Salarie).get(s.n2_id) if s.n2_id else None
        d = SalarieOut.model_validate(s)
        d.n1_nom = n1.full_name if n1 else None
        d.n2_nom = n2.full_name if n2 else None
        out.append(d)
    return out


@router.post("/salaries", response_model=SalarieOut, status_code=201)
def create_salarie(p: SalarieIn, db: Session = Depends(get_db)):
    verifier_refs_actifs(db, p)   # PATCH 12 (création)
    if db.query(Salarie).filter(Salarie.matricule == p.matricule).first():
        raise HTTPException(409, "Matricule déjà utilisé.")
    obj = Salarie(**p.model_dump())
    db.add(obj); db.commit(); db.refresh(obj)
    return obj


@router.put("/salaries/{salarie_id}", response_model=SalarieOut)
def update_salarie(salarie_id: int, p: SalarieIn, db: Session = Depends(get_db),
                   admin: Salarie = Depends(require_admin)):
    verifier_refs_actifs(db, p)   # PATCH 12 (modification)
    obj = db.query(Salarie).get(salarie_id)
    if not obj:
        raise HTTPException(404, "Introuvable.")
    if salarie_id == p.n1_id:
        raise HTTPException(422, "Un salarié ne peut être son propre N+1.")
    if salarie_id == p.n2_id:
        raise HTTPException(422, "Un salarié ne peut être son propre N+2.")
    if salarie_id == admin.id:
        # Un Admin ne peut ni se rétrograder ni se désactiver lui-même.
        if obj.is_admin and not p.is_admin:
            raise HTTPException(422, "Vous ne pouvez pas retirer votre propre statut Admin.")
        if obj.is_active and not p.is_active:
            raise HTTPException(422, "Vous ne pouvez pas désactiver votre propre compte.")
    # Ne pas retirer le statut Admin du dernier Administrateur.
    if obj.is_admin and not p.is_admin and \
            db.query(Salarie).filter(Salarie.is_admin.is_(True)).count() <= 1:
        raise HTTPException(422, "Il doit rester au moins un compte Administrateur.")
    for k, v in p.model_dump().items():
        setattr(obj, k, v)
    db.commit(); db.refresh(obj)
    return obj


@router.delete("/salaries/{salarie_id}", response_model=MessageResponse)
def delete_salarie(salarie_id: int, db: Session = Depends(get_db)):
    """Suppression bloquée si le salarié est référencé (N+1 de quelqu'un)."""
    obj = db.query(Salarie).get(salarie_id)
    if not obj:
        raise HTTPException(404, "Introuvable.")
    if db.query(func.count(Salarie.id)).filter(Salarie.n1_id == salarie_id).scalar():
        raise HTTPException(409, "Ce salarié est le N+1 de collaborateurs : suppression bloquée.")
    db.delete(obj); db.commit()
    return MessageResponse(detail="Supprimé.")


# ================== PATCH 2 : CRUD complementaire (M5) ==================
# Endpoints PUT/DELETE manquants pour les formulaires du parametrage M5.

@router.put("/departements/{item_id}", response_model=DepartementOut)
def update_departement(item_id: int, p: SimpleRef, site_id: int | None = None,
                       db: Session = Depends(get_db)):
    obj = db.query(Departement).get(item_id)
    if not obj:
        raise HTTPException(404, "Introuvable.")
    obj.code, obj.libelle, obj.site_id = p.code, p.libelle, site_id
    db.commit(); db.refresh(obj)
    return obj


@router.delete("/departements/{item_id}", response_model=MessageResponse)
def delete_departement(item_id: int, db: Session = Depends(get_db)):
    obj = db.query(Departement).get(item_id)
    if not obj:
        raise HTTPException(404, "Introuvable.")
    if db.query(Section).filter(Section.departement_id == item_id).first() \
            or db.query(Salarie).filter(Salarie.departement_id == item_id).first():
        raise HTTPException(409, "Departement reference par des sections ou salaries.")
    db.delete(obj); db.commit()
    return MessageResponse(detail="Supprime.")


@router.put("/sections/{item_id}", response_model=SectionOut)
def update_section(item_id: int, p: SimpleRef, departement_id: int,
                   db: Session = Depends(get_db)):
    obj = db.query(Section).get(item_id)
    if not obj:
        raise HTTPException(404, "Introuvable.")
    obj.code, obj.libelle, obj.departement_id = p.code, p.libelle, departement_id
    db.commit(); db.refresh(obj)
    return obj


@router.delete("/sections/{item_id}", response_model=MessageResponse)
def delete_section(item_id: int, db: Session = Depends(get_db)):
    obj = db.query(Section).get(item_id)
    if not obj:
        raise HTTPException(404, "Introuvable.")
    if db.query(Salarie).filter(Salarie.section_id == item_id).first():
        raise HTTPException(409, "Section referencee par des salaries.")
    db.delete(obj); db.commit()
    return MessageResponse(detail="Supprime.")


@router.put("/emplois/{item_id}", response_model=EmploiOut)
def update_emploi(item_id: int, p: SimpleRef, famille: int,
                  db: Session = Depends(get_db)):
    if famille not in (1, 2, 3):
        raise HTTPException(422, "famille doit valoir 1, 2 ou 3.")
    obj = db.query(Emploi).get(item_id)
    if not obj:
        raise HTTPException(404, "Introuvable.")
    obj.code, obj.libelle, obj.famille = p.code, p.libelle, famille
    db.commit(); db.refresh(obj)
    return obj


@router.delete("/emplois/{item_id}", response_model=MessageResponse)
def delete_emploi(item_id: int, db: Session = Depends(get_db)):
    obj = db.query(Emploi).get(item_id)
    if not obj:
        raise HTTPException(404, "Introuvable.")
    if db.query(Salarie).filter(Salarie.emploi_id == item_id).first():
        raise HTTPException(409, "Emploi reference par des salaries.")
    db.query(EmploiProfil).filter(EmploiProfil.emploi_id == item_id).delete()
    db.delete(obj); db.commit()
    return MessageResponse(detail="Supprime.")


@router.put("/criteres/{item_id}", response_model=CritereOut)
def update_critere(item_id: int, p: CritereIn, db: Session = Depends(get_db)):
    obj = db.query(Critere).get(item_id)
    if not obj:
        raise HTTPException(404, "Introuvable.")
    obj.code, obj.libelle, obj.actif = p.code, p.libelle, p.actif
    obj.editable = p.editable   # PATCH 12
    db.query(CritereDetail).filter(CritereDetail.critere_id == item_id).delete()
    for d in p.details:
        db.add(CritereDetail(critere_id=item_id, libelle_descriptif=d.libelle_descriptif,
                             valeur=d.valeur, ordre=d.ordre, sens=d.sens,  # PATCH 12 (maj)
                             valeur_min=d.valeur_min, valeur_max=d.valeur_max,
                             actif=d.actif))
    db.commit(); db.refresh(obj)
    return obj


@router.delete("/criteres/{item_id}", response_model=MessageResponse)
def delete_critere(item_id: int, db: Session = Depends(get_db)):
    obj = db.query(Critere).get(item_id)
    if not obj:
        raise HTTPException(404, "Introuvable.")
    if db.query(ProfilCritere).filter(ProfilCritere.critere_id == item_id).first():
        raise HTTPException(409, "Critere utilise par des profils.")
    db.query(CritereDetail).filter(CritereDetail.critere_id == item_id).delete()
    db.delete(obj); db.commit()
    return MessageResponse(detail="Supprime.")


@router.put("/profils/{item_id}", response_model=MessageResponse)
def update_profil(item_id: int, p: ProfilIn, db: Session = Depends(get_db)):
    obj = db.query(Profil).get(item_id)
    if not obj:
        raise HTTPException(404, "Introuvable.")
    obj.code, obj.libelle = p.code, p.libelle
    db.query(ProfilCritere).filter(ProfilCritere.profil_id == item_id).delete()
    for c in p.criteres:
        db.add(ProfilCritere(profil_id=item_id, critere_id=c.critere_id,
                             coefficient=c.coefficient, ordre=c.ordre))
    db.commit()
    return MessageResponse(detail="Profil mis a jour.")


@router.delete("/profils/{item_id}", response_model=MessageResponse)
def delete_profil(item_id: int, db: Session = Depends(get_db)):
    obj = db.query(Profil).get(item_id)
    if not obj:
        raise HTTPException(404, "Introuvable.")
    if db.query(EmploiProfil).filter(EmploiProfil.profil_id == item_id).first():
        raise HTTPException(409, "Profil attribue a des emplois.")
    db.query(ProfilCritere).filter(ProfilCritere.profil_id == item_id).delete()
    db.delete(obj); db.commit()
    return MessageResponse(detail="Supprime.")


@router.patch("/salaries/{salarie_id}/toggle-active", response_model=MessageResponse)
def toggle_active(salarie_id: int, db: Session = Depends(get_db),
                  admin: Salarie = Depends(require_admin)):
    """Active/désactive le compte d'un salarié (connexion impossible si inactif,
    fiches existantes conservées). Tâche Admin/managers."""
    obj = db.query(Salarie).get(salarie_id)
    if not obj:
        raise HTTPException(404, "Introuvable.")
    if obj.is_admin:
        raise HTTPException(422, "Impossible de désactiver un compte Admin.")
    obj.is_active = not obj.is_active
    db.commit()
    etat = "activé" if obj.is_active else "désactivé"
    return MessageResponse(detail=f"Compte {obj.matricule} {etat}.")


# ================== PATCH 9 : réinitialisation des mots de passe ==================
@router.post("/salaries/{salarie_id}/reset-password", response_model=MessageResponse)
def reset_password(salarie_id: int, db: Session = Depends(get_db),
                   admin: Salarie = Depends(require_admin)):
    """Oubli de mot de passe : l'Admin vide le hash ; le salarié recrée son
    mot de passe à sa prochaine connexion (parcours 1re connexion)."""
    obj = db.query(Salarie).get(salarie_id)
    if not obj:
        raise HTTPException(404, "Introuvable.")
    obj.password_hash = None
    obj.must_change_password = True
    log_action(db, auteur_id=admin.id, action="RESET_PASSWORD",
               table_cible="salaries", enregistrement_id=obj.id)
    db.commit()
    return MessageResponse(detail=f"Mot de passe de {obj.matricule} réinitialisé : "
                                   f"il devra en créer un nouveau à sa prochaine connexion.")


@router.post("/salaries/reset-passwords", response_model=MessageResponse)
def reset_all_passwords(db: Session = Depends(get_db),
                        admin: Salarie = Depends(require_admin)):
    """Réinitialisation globale (sauf comptes Admin) : chaque salarié recrée
    son mot de passe à sa prochaine connexion."""
    n = 0
    for s in db.query(Salarie).filter(Salarie.is_admin.is_(False)).all():
        s.password_hash = None
        s.must_change_password = True
        n += 1
    log_action(db, auteur_id=admin.id, action="RESET_ALL_PASSWORDS",
               table_cible="salaries", enregistrement_id=0)
    db.commit()
    return MessageResponse(detail=f"{n} mot(s) de passe réinitialisé(s).")


# ================== PATCH 12 : actif référentiels + bibliothèque détails ==================

_REF_ACTIF = {
    "sites": Site, "departements": Departement, "sections": Section,
    "emplois": Emploi, "categories": Categorie, "postes": Poste,
}


@router.patch("/{table}/{item_id}/toggle-active", response_model=MessageResponse)
def toggle_ref_actif(table: str, item_id: int, db: Session = Depends(get_db),
                      admin: Salarie = Depends(require_admin)):
    """PATCH 12 — active/désactive un référentiel. Un référentiel désactivé
    n'est plus pris en compte à la génération des fiches (cascade) et ne peut
    plus recevoir de nouveaux rattachements salariés."""
    model = _REF_ACTIF.get(table)
    if not model:
        raise HTTPException(422, "Table non supportée pour le toggle actif.")
    obj = db.query(model).get(item_id)
    if not obj:
        raise HTTPException(404, "Introuvable.")
    obj.actif = not obj.actif
    log_action(db, auteur_id=admin.id, action="TOGGLE_ACTIF",
               table_cible=table, enregistrement_id=obj.id)
    db.commit()
    etat = "activé" if obj.actif else "désactivé"
    return MessageResponse(detail=f"{obj.code} {etat}.")


def verifier_refs_actifs(db: Session, p) -> None:
    """PATCH 12 — refuse le rattachement d'un salarié à un référentiel désactivé."""
    from app.models.rating import Categorie, Departement, Emploi, Poste, Section, Site
    couples = [(p.site_id, Site, "site"), (p.departement_id, Departement, "département"),
               (p.section_id, Section, "section"), (p.emploi_id, Emploi, "emploi"),
               (p.categorie_id, Categorie, "catégorie"), (p.poste_id, Poste, "poste")]
    for ref_id, model, nom in couples:
        if ref_id is None:
            continue
        o = db.query(model).get(ref_id)
        if o is None:
            raise HTTPException(422, f"{nom.capitalize()} introuvable.")
        if not getattr(o, "actif", True):
            raise HTTPException(422, f"Le {nom} « {o.libelle} » est désactivé : rattachement impossible.")


def _detail_ok(p) -> None:
    if p.sens == 2 and (p.valeur_min is None or p.valeur_max is None):
        raise HTTPException(422, "Valeur à intervalle : MIN et MAX obligatoires.")


@router.get("/details-criteres", response_model=list[CritereDetailOut])
def list_details_criteres(db: Session = Depends(get_db)):
    """PATCH 12 — bibliothèque de tous les détails critères (y compris non assemblés)."""
    return db.query(CritereDetail).order_by(CritereDetail.ordre, CritereDetail.id).all()


@router.post("/details-criteres", response_model=CritereDetailOut, status_code=201)
def create_detail_critere(p: CritereDetailIn, db: Session = Depends(get_db)):
    _detail_ok(p)
    obj = CritereDetail(critere_id=None, libelle_descriptif=p.libelle_descriptif,
                        valeur=p.valeur, ordre=p.ordre, sens=p.sens,
                        valeur_min=p.valeur_min, valeur_max=p.valeur_max, actif=p.actif)
    db.add(obj); db.commit(); db.refresh(obj)
    return obj


@router.put("/details-criteres/{item_id}", response_model=CritereDetailOut)
def update_detail_critere(item_id: int, p: CritereDetailIn,
                          db: Session = Depends(get_db)):
    obj = db.query(CritereDetail).get(item_id)
    if not obj:
        raise HTTPException(404, "Introuvable.")
    _detail_ok(p)
    obj.libelle_descriptif, obj.valeur, obj.ordre = p.libelle_descriptif, p.valeur, p.ordre
    obj.sens, obj.valeur_min, obj.valeur_max, obj.actif = p.sens, p.valeur_min, p.valeur_max, p.actif
    db.commit(); db.refresh(obj)
    return obj


@router.delete("/details-criteres/{item_id}", response_model=MessageResponse)
def delete_detail_critere(item_id: int, db: Session = Depends(get_db)):
    obj = db.query(CritereDetail).get(item_id)
    if not obj:
        raise HTTPException(404, "Introuvable.")
    if db.query(EvaluationLigne).filter(EvaluationLigne.critere_detail_id == item_id).first():
        raise HTTPException(409, "Détail utilisé par des fiches : suppression bloquée.")
    db.delete(obj); db.commit()
    return MessageResponse(detail="Supprimé.")
