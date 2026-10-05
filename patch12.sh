#!/usr/bin/env bash
# ============================================================================
# PATCH 12 — EVALPOINT (rating-dev) — 2026-10-05
# À exécuter DEPUIS LA RACINE du dépôt :  bash patch12.sh
# IDEMPOTENT : chaque modification est gardée par un marqueur littéral ;
# ré-exécuter le script ne duplique RIEN (leçon des patchs 9/10/11).
#
# Contenu :
#  1. Modèles DB : actif sur 6 référentiels, editable sur critères,
#     sens/valeur_min/valeur_max/actif sur détails, nature sur salariés,
#     valeur_choisie sur lignes, table evaluation_criteres (libellés A REMPLIR)
#  2. Génération des fiches : cascade des référentiels actifs
#     + pré-remplissage des critères éditables avec les objectifs N-1
#  3. QCM : détails à intervalle -> 3 étoiles (min / milieu / max),
#     normalisation /5 par diviseur (max/5) dans notations et navigation
#  4. Référentiel M5 : ordre onglets, onglet Détails Critères (bibliothèque),
#     colonnes Nb Salariés + Actif (toggle), champ NATURE, combobox CODE — LIBELLÉ,
#     editable + type valeur dans le formulaire critères, Admins en tête
#  5. Benchmark : dé-anonymisé + recherche/tri ; NAVIGATION : filtre par section
#  6. UI : pagination corrigée, menu mobile sans EVALUATIONS, topbar sans logout
# ============================================================================
set -u
cd "$(dirname "$0")"
echo "=== PATCH 12 — édition des fichiers ==="
python3 - <<'PYEOF'
import re, ast, pathlib

ROOT = pathlib.Path(".")
def rd(p): return (ROOT / p).read_text(encoding="utf-8")
def wr(p, c): (ROOT / p).write_text(c, encoding="utf-8")

def sub(p, old, new, mk=None, n=1, regex=False, optional=False, literal=True):
    """Remplace old->new (1 fois). Idempotence : saute si le marqueur littéral
    mk, ou le texte inséré new, est déjà présent dans le fichier."""
    c = rd(p)
    if (mk and mk in c) or (literal and new in c):
        print(f"  SKIP  {p} :: {mk or 'déjà appliqué'}")
        return
    if regex:
        c2, k = re.subn(old, new, c, count=n, flags=re.S)
    else:
        k, c2 = (1, c.replace(old, new, 1)) if old in c else (0, c)
    if k == 0:
        if optional:
            print(f"  ??    {p} :: ancre non trouvée (optionnel) : {str(old)[:60]}")
            return
        raise SystemExit(f"ERREUR : ancre introuvable dans {p}\n--- {str(old)[:300]}")
    wr(p, c2)
    print(f"  OK    {p} :: {mk or str(old)[:46]}")

def rewrite(p, content, mk):
    c = rd(p)
    if mk in c:
        print(f"  SKIP  {p} :: {mk} déjà présent")
        return
    wr(p, content)
    print(f"  OK    {p} :: réécrit ({mk})")

def append_block(p, block, mk):
    c = rd(p)
    if mk in c:
        print(f"  SKIP  {p} :: {mk} déjà présent")
        return
    if not c.endswith("\n"): c += "\n"
    wr(p, c + block)
    print(f"  OK    {p} :: + {mk}")

def pycheck(p):
    try:
        ast.parse(rd(p)); print(f"  AST OK {p}")
    except SyntaxError as e:
        raise SystemExit(f"ERREUR SYNTAXE {p} ligne {e.lineno} : {e.msg}")

# ============================== 1. MODÈLES ==================================
p = "backend/app/models/rating.py"
for cls, term in [("Site", "libelle"), ("Departement", "libelle"),
                  ("Section", "libelle"), ("Categorie", "libelle"),
                  ("Poste", "libelle")]:
    act = f'    actif: Mapped[bool] = mapped_column(Boolean, default=True)  # PATCH 12 ({cls})\n'
    sub(p, r'(class ' + cls + r'\(Base\):[\s\S]*?libelle: Mapped\[str\] = mapped_column\(VARCHAR\(120\)\)\n)',
        r'\1' + act, mk=f"PATCH 12 ({cls})", regex=True)
act = '    actif: Mapped[bool] = mapped_column(Boolean, default=True)  # PATCH 12 (Emploi)\n'
sub(p, r'(class Emploi\(Base\):[\s\S]*?famille: Mapped\[int\] = mapped_column\(SmallInteger\)[^\n]*\n)',
    r'\1' + act, mk="PATCH 12 (Emploi)", regex=True)
# critères : editable
sub(p, r'(    actif: Mapped\[bool\] = mapped_column\(Boolean, default=True\)\n)',
    r'\1    editable: Mapped[bool] = mapped_column(Boolean, default=False)  # PATCH 12 — « A REMPLIR »\n',
    mk="editable: Mapped[bool]", regex=True)
# détails : critere_id nullable + sens/min/max/actif
sub(p, r'(__tablename__ = "critere_details"\s*\n\s*id: Mapped\[int\] = mapped_column\(primary_key=True\)\s*\n\s*)'
        r'critere_id: Mapped\[int\] = mapped_column\(ForeignKey\("criteres\.id"\)\)',
    r'\1critere_id: Mapped[int | None] = mapped_column(ForeignKey("criteres.id"), nullable=True)  # PATCH 12 : bibliothèque',
    mk="PATCH 12 : bibliothèque", regex=True)
sub(p, r'(    valeur: Mapped\[float\] = mapped_column\(Numeric\(5, 2\)\)\n)',
    r'''\1    sens: Mapped[int] = mapped_column(SmallInteger, default=1)   # PATCH 12 : 1=unique, 2=intervalle
    valeur_min: Mapped[float | None] = mapped_column(Numeric(5, 2), nullable=True)  # PATCH 12
    valeur_max: Mapped[float | None] = mapped_column(Numeric(5, 2), nullable=True)  # PATCH 12
    actif: Mapped[bool] = mapped_column(Boolean, default=True)  # PATCH 12 (détail)
''',
    mk="PATCH 12 : 1=unique, 2=intervalle", regex=True)
# salarié : nature
sub(p, r'(    hors_evaluation: Mapped\[bool\] = mapped_column\(Boolean, default=False\)\n)',
    r'\1    nature: Mapped[str] = mapped_column(VARCHAR(20), default="Embauché")  # PATCH 12 : Embauché/Journalier/Contractuel/Stagiaire/Apprenti\n',
    mk="PATCH 12 : Embauché/Journalier", regex=True)
# lignes : valeur_choisie (étoiles intervalle)
sub(p, r'(    critere_detail_id: Mapped\[int \| None\][\s\S]*?nullable=True\s*\)\n)',
    r'\1    valeur_choisie: Mapped[float | None] = mapped_column(Numeric(5, 2), nullable=True)  # PATCH 12 : étoiles intervalle\n',
    mk="PATCH 12 : étoiles intervalle", regex=True)
append_block(p, '''
# ================== PATCH 12 : libellés « A REMPLIR » par fiche ==================

class EvaluationCritere(Base):
    """PATCH 12 — libellé de critère personnalisé pour UNE fiche (objectifs N-1 -> N,
    critères editable dont le libellé par défaut est « A REMPLIR »)."""
    __tablename__ = "evaluation_criteres"
    id: Mapped[int] = mapped_column(primary_key=True)
    evaluation_id: Mapped[int] = mapped_column(ForeignKey("evaluations.id"))
    critere_id: Mapped[int] = mapped_column(ForeignKey("criteres.id"))
    libelle: Mapped[str] = mapped_column(VARCHAR(300))
    __table_args__ = (UniqueConstraint("evaluation_id", "critere_id"),)
''', "class EvaluationCritere")
pycheck(p)

# ====================== 2. SCHÉMAS RÉFÉRENTIEL (réécrit) ====================
rewrite("backend/app/schemas/referentiel.py", '''# 2026-10-05 PATCH 12 — schémas du référentiel (M5) : actif, editable,
# type valeur (unique/intervalle), nature salarié, bibliothèque détails.
from datetime import date
from pydantic import BaseModel, Field


class SimpleRef(BaseModel):
    id: int
    code: str
    libelle: str
    actif: bool = True                      # PATCH 12
    model_config = {"from_attributes": True}


class DepartementOut(SimpleRef):
    site_id: int | None = None


class SectionOut(SimpleRef):
    departement_id: int


class EmploiOut(SimpleRef):
    famille: int
    profils: list[SimpleRef] = []


class CritereDetailIn(BaseModel):
    libelle_descriptif: str = Field(min_length=3, max_length=300)
    valeur: float = Field(ge=0, le=100)
    ordre: int = 0
    sens: int = Field(default=1, ge=1, le=2)          # PATCH 12 : 1 unique / 2 intervalle
    valeur_min: float | None = None                   # PATCH 12
    valeur_max: float | None = None                   # PATCH 12
    actif: bool = True                                # PATCH 12


class CritereDetailOut(BaseModel):
    id: int
    critere_id: int | None = None                      # PATCH 12 : null = bibliothèque
    libelle_descriptif: str
    valeur: float
    ordre: int
    sens: int = 1                                      # PATCH 12
    valeur_min: float | None = None                    # PATCH 12
    valeur_max: float | None = None                    # PATCH 12
    actif: bool = True                                 # PATCH 12
    model_config = {"from_attributes": True}


class CritereOut(BaseModel):
    id: int
    code: str
    libelle: str
    actif: bool
    editable: bool = False                             # PATCH 12
    details: list[CritereDetailOut] = []
    model_config = {"from_attributes": True}


class CritereIn(BaseModel):
    code: str
    libelle: str
    actif: bool = True
    editable: bool = False                             # PATCH 12
    details: list[CritereDetailIn] = []


class ProfilCritereIn(BaseModel):
    critere_id: int
    coefficient: float = Field(gt=0)
    ordre: int = 0


class ProfilOut(BaseModel):
    id: int
    code: str
    libelle: str
    criteres: list[dict] = []
    model_config = {"from_attributes": True}


class ProfilIn(BaseModel):
    code: str
    libelle: str
    criteres: list[ProfilCritereIn] = []


class EmploiProfilsIn(BaseModel):
    profils: list[int] = []   # ids ordonnés des profils attribués


class SalarieIn(BaseModel):
    matricule: str
    nom: str
    prenoms: str | None = None
    site_id: int | None = None
    departement_id: int | None = None
    section_id: int | None = None
    emploi_id: int | None = None
    categorie_id: int | None = None
    poste_id: int | None = None
    date_embauche: date | None = None
    email: str | None = None
    n1_id: int | None = None
    n2_id: int | None = None
    hors_evaluation: bool = False
    nature: str = "Embauché"                            # PATCH 12
    is_admin: bool = False
    is_active: bool = True


class SalarieOut(SalarieIn):
    id: int
    n1_nom: str | None = None
    n2_nom: str | None = None
    model_config = {"from_attributes": True}
''', "PATCH 12 — schémas du référentiel")

# ========================== 3. SCHÉMAS ÉVALUATION ===========================
p = "backend/app/schemas/evaluation.py"
sub(p, r'(class QcmIn\(BaseModel\):[\s\S]*?critere_detail_id: int\n)',
    r'\1    valeur_choisie: float | None = None        # PATCH 12 : étoiles intervalle\n',
    mk="valeur_choisie: float | None", regex=True)
sub(p, r'(    coefficient: float\n)',
    r'''\1    editable: bool = False                      # PATCH 12 : libellé « A REMPLIR »
    libelle_perso: str | None = None              # PATCH 12 : pré-rempli objectifs N-1
''',
    mk="libelle_perso: str | None", regex=True)
pycheck(p)

# ============================ 4. SCHÉMA CAMPAGNE ============================
sub("backend/app/schemas/campagne.py", r'class GenerationReport\(BaseModel\):\n',
    'class GenerationReport(BaseModel):\n'
    '    exclus_inactifs: int = 0        # PATCH 12 : référentiels désactivés\n'
    '    objectifs_prefilles: int = 0    # PATCH 12 : critères A REMPLIR pré-remplis\n',
    mk="objectifs_prefilles: int", regex=True)
pycheck("backend/app/schemas/campagne.py")

# ========================= 5. SERVICE NOTATION (/5) =========================
p = "backend/app/services/notation.py"
append_block(p, '''

# ================== PATCH 12 : normalisation des détails à intervalle ==================

def note_detail(detail, valeur_choisie=None) -> float:
    """Note /5 d'un détail coché. Valeur unique -> valeur brute.
    Intervalle (sens=2) -> valeur choisie (étoiles) normalisée par diviseur
    max/5 (ex. 7-9 sur 20 -> 7/4=1.75 .. 9/4=2.25 sur 5)."""
    v = valeur_choisie if valeur_choisie is not None else float(detail.valeur)
    sens = getattr(detail, "sens", 1) or 1
    vmax = getattr(detail, "valeur_max", None)
    if sens == 2 and vmax:
        return round(float(v) * 5.0 / float(vmax), 2)
    return round(float(v), 2)
''', "def note_detail")
pycheck(p)

# ===================== 6. SERVICE CAMPAGNE (réécrit) =======================
rewrite("backend/app/services/campagne.py", '''# 2026-10-05 PATCH 12 — génération des fiches : idempotente, par famille,
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
''', "_prefill_objectifs")

# ============================ 7. API RÉFÉRENTIEL ============================
p = "backend/app/api/referentiel.py"
# Admins en tête
sub(p, r'def list_salaries\(db: Session = Depends\(get_db\)\):\s*\n\s*salaries = db\.query\(Salarie\)\.order_by\(Salarie\.matricule\)',
    'def list_salaries(db: Session = Depends(get_db)):\n'
    '    salaries = db.query(Salarie).order_by(Salarie.is_admin.desc(), Salarie.matricule)  # PATCH 12 : Admins en tête',
    mk="PATCH 12 : Admins en tête", regex=True)
# Blocage création/modif salarié sur référentiel désactivé
sub(p, r'(def create_salarie\(p: SalarieIn, db: Session = Depends\(get_db\)\):\s*\n)'
        r'(\s*)if db\.query\(Salarie\)\.filter\(Salarie\.matricule == p\.matricule\)\.first\(\):',
    r'\1\2verifier_refs_actifs(db, p)   # PATCH 12 (création)\n'
    r'\2if db.query(Salarie).filter(Salarie.matricule == p.matricule).first():',
    mk="PATCH 12 (création)", regex=True)
sub(p, r'(def update_salarie\(salarie_id: int, p: SalarieIn, db: Session = Depends\(get_db\),\s*\n'
        r'\s*admin: Salarie = Depends\(require_admin\)\):\s*\n)'
        r'(\s*)obj = db\.query\(Salarie\)\.get\(salarie_id\)',
    r'\1\2verifier_refs_actifs(db, p)   # PATCH 12 (modification)\n'
    r'\2obj = db.query(Salarie).get(salarie_id)',
    mk="PATCH 12 (modification)", regex=True)
# critères : editable + champs détails
sub(p, r'obj = Critere\(code=p\.code, libelle=p\.libelle, actif=p\.actif\)',
    'obj = Critere(code=p.code, libelle=p.libelle, actif=p.actif, editable=p.editable)  # PATCH 12',
    mk="editable=p.editable)  # PATCH 12", regex=True)
sub(p, r'CritereDetail\(critere_id=obj\.id, libelle_descriptif=d\.libelle_descriptif,\s*\n'
        r'\s*valeur=d\.valeur, ordre=d\.ordre\)\)',
    'CritereDetail(critere_id=obj.id, libelle_descriptif=d.libelle_descriptif,\n'
    '                             valeur=d.valeur, ordre=d.ordre, sens=d.sens,  # PATCH 12 (création)\n'
    '                             valeur_min=d.valeur_min, valeur_max=d.valeur_max,\n'
    '                             actif=d.actif))',
    mk="PATCH 12 (création)\n", regex=True)
sub(p, r'obj\.code, obj\.libelle, obj\.actif = p\.code, p\.libelle, p\.actif',
    'obj.code, obj.libelle, obj.actif = p.code, p.libelle, p.actif\n'
    '    obj.editable = p.editable   # PATCH 12', mk="obj.editable = p.editable", regex=True)
sub(p, r'CritereDetail\(critere_id=item_id, libelle_descriptif=d\.libelle_descriptif,\s*\n'
        r'\s*valeur=d\.valeur, ordre=d\.ordre\)\)',
    'CritereDetail(critere_id=item_id, libelle_descriptif=d.libelle_descriptif,\n'
    '                             valeur=d.valeur, ordre=d.ordre, sens=d.sens,  # PATCH 12 (maj)\n'
    '                             valeur_min=d.valeur_min, valeur_max=d.valeur_max,\n'
    '                             actif=d.actif))',
    mk="PATCH 12 (maj)\n", regex=True)
sub(p, r'from app\.schemas\.referentiel import \(\s*\n'
        r'\s*CritereDetailIn, CritereIn, CritereOut, DepartementOut, EmploiOut,',
    'from app.schemas.referentiel import (\n'
    '    CritereDetailIn, CritereDetailOut, CritereIn, CritereOut, DepartementOut, EmploiOut,',
    mk="CritereDetailIn, CritereDetailOut", regex=True)
sub(p, r'from app\.models\.rating import \(\s*\n'
        r'\s*Categorie, Critere, CritereDetail, Departement, Emploi, EmploiProfil,\s*\n'
        r'\s*Poste, Profil, ProfilCritere, Salarie, Section, Site,\s*\n\)',
    'from app.models.rating import (\n'
    '    Categorie, Critere, CritereDetail, Departement, Emploi, EmploiProfil,\n'
    '    EvaluationLigne, Poste, Profil, ProfilCritere, Salarie, Section, Site,  # PATCH 12\n'
    ')',
    mk="EvaluationLigne, Poste, Profil", regex=True)
append_block(p, '''

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
''', "PATCH 12 : actif référentiels")
pycheck(p)

# ============================ 8. API ÉVALUATIONS ============================
p = "backend/app/api/evaluations.py"
sub(p, r'Approbation, Critere, CritereDetail, EmploiProfil, Evaluation,\s*\n'
        r'\s*EvaluationLigne, Poste, Profil, ProfilCritere, Salarie,',
    'Approbation, Critere, CritereDetail, EmploiProfil, Evaluation,\n'
    '    EvaluationCritere, EvaluationLigne, Poste, Profil, ProfilCritere, Salarie,  # PATCH 12',
    mk="EvaluationCritere, EvaluationLigne", regex=True)
sub(p, r'details = db\.query\(CritereDetail\)\\?\s*\n'
        r'\s*\.filter\(CritereDetail\.critere_id == pc\.critere_id\)\\?\s*\n'
        r'\s*\.order_by\(CritereDetail\.ordre\)\.all\(\)',
    'details = db.query(CritereDetail) \\\n'
    '                .filter(CritereDetail.critere_id == pc.critere_id,\n'
    '                        CritereDetail.actif.is_(True)) \\\n'
    '                .order_by(CritereDetail.ordre).all()  # PATCH 12 : détails actifs',
    mk="PATCH 12 : détails actifs", regex=True)
sub(p, r'(            ln = par_cle\.get\(\(pid, pc\.critere_id, "N"\)\)\s*\n'
        r'\s*ln1 = par_cle\.get\(\(pid, pc\.critere_id, "N\+1"\)\)\s*\n)',
    r'''\1            ec = db.query(EvaluationCritere).filter(                 # PATCH 12 : libellé perso
                EvaluationCritere.evaluation_id == e.id,
                EvaluationCritere.critere_id == pc.critere_id).first()
''',
    mk="ec = db.query(EvaluationCritere)", regex=True)
sub(p, r'critere_libelle=c\.libelle if c else "",',
    'critere_libelle=(ec.libelle if ec else (c.libelle if c else "")),  # PATCH 12 : A REMPLIR remplacé\n'
    '                editable=(c.editable if c else False),\n'
    '                libelle_perso=(ec.libelle if ec else None),',
    mk="libelle_perso=(ec.libelle", regex=True)
sub(p, r'details=\[\{"id": d\.id, "libelle": d\.libelle_descriptif\}\s*\n\s*for d in details\],',
    'details=[{"id": d.id, "libelle": d.libelle_descriptif,\n'
    '                          "sens": d.sens,\n'
    '                          "valeur_min": float(d.valeur_min) if d.valeur_min is not None else None,\n'
    '                          "valeur_max": float(d.valeur_max) if d.valeur_max is not None else None}]  # PATCH 12\n'
    '                         for d in details],',
    mk='"sens": d.sens', regex=True)
sub(p, r'    detail = db\.query\(CritereDetail\)\.get\(p\.critere_detail_id\)\s*\n'
        r'\s*if not detail or detail\.critere_id != p\.critere_id:\s*\n'
        r'\s*raise HTTPException\(422, "Détail de critère invalide pour ce critère\."\)',
    '    detail = db.query(CritereDetail).get(p.critere_detail_id)\n'
    '    if not detail or detail.critere_id != p.critere_id:\n'
    '        raise HTTPException(422, "Détail de critère invalide pour ce critère.")\n'
    '    if not detail.actif:   # PATCH 12 : étoiles intervalle\n'
    '        raise HTTPException(422, "Détail de critère désactivé.")\n'
    '    valeur_choisie = None\n'
    '    if (detail.sens or 1) == 2:\n'
    '        vmin = float(detail.valeur_min if detail.valeur_min is not None else detail.valeur)\n'
    '        vmax = float(detail.valeur_max if detail.valeur_max is not None else detail.valeur)\n'
    '        valeur_choisie = float(p.valeur_choisie) if p.valeur_choisie is not None else vmin\n'
    '        if not (min(vmin, vmax) - 1e-9 <= valeur_choisie <= max(vmin, vmax) + 1e-9):\n'
    '            raise HTTPException(422, f"Valeur étoile hors intervalle [{min(vmin, vmax)} ; {max(vmin, vmax)}].")',
    mk="PATCH 12 : étoiles intervalle\n    if not detail.actif", regex=True)
sub(p, r'        ligne\.critere_detail_id = p\.critere_detail_id\s*\n'
        r'\s*ligne\.commentaire = p\.commentaire\.strip\(\)',
    '        ligne.critere_detail_id = p.critere_detail_id\n'
    '        ligne.commentaire = p.commentaire.strip()\n'
    '        ligne.valeur_choisie = valeur_choisie   # PATCH 12',
    mk="ligne.valeur_choisie = valeur_choisie", regex=True)
sub(p, r'            critere_detail_id=p\.critere_detail_id,\s*\n'
        r'\s*commentaire=p\.commentaire\.strip\(\),\s*\n\s*\)',
    '            critere_detail_id=p.critere_detail_id,\n'
    '            commentaire=p.commentaire.strip(),\n'
    '            valeur_choisie=valeur_choisie,  # PATCH 12\n'
    '        )',
    mk="valeur_choisie=valeur_choisie", regex=True)
append_block(p, '''

# ================== PATCH 12 : libellé des critères « A REMPLIR » ==================

@router.post("/{evaluation_id}/libelle-critere", response_model=MessageResponse)
def libelle_critere(evaluation_id: int, p: dict, db: Session = Depends(get_db),
                    user: Salarie = Depends(get_current_user)):
    """Critère editable : le salarié (N) précise le libellé de son objectif.
    Pré-rempli à la génération par les objectifs de la campagne précédente."""
    e = db.query(Evaluation).get(evaluation_id)
    if not e:
        raise HTTPException(404, "Fiche introuvable.")
    role = mon_role(db, e, user)
    if role != "N":
        raise HTTPException(403, "Seul le salarié peut renseigner le libellé de son objectif.")
    critere_id, libelle = p.get("critere_id"), (p.get("libelle") or "").strip()
    if not critere_id or len(libelle) < 3:
        raise HTTPException(422, "critere_id et libellé (3 caractères min.) obligatoires.")
    c = db.query(Critere).get(critere_id)
    if not c or not c.editable:
        raise HTTPException(422, "Ce critère n'est pas modifiable.")
    ec = db.query(EvaluationCritere).filter(
        EvaluationCritere.evaluation_id == evaluation_id,
        EvaluationCritere.critere_id == critere_id).first()
    if ec:
        ec.libelle = libelle
    else:
        db.add(EvaluationCritere(evaluation_id=evaluation_id,
                                 critere_id=critere_id, libelle=libelle))
    db.commit()
    return MessageResponse(detail="Libellé du critère enregistré.")
''', "libelle-critere")
pycheck(p)

# ============================ 9. API NOTATIONS ==============================
p = "backend/app/api/notations.py"
sub(p, r'from app\.services\.notation import calc_note_globale, calc_rate, calc_valeur, est_divergente',
    'from app.services.notation import (calc_note_globale, calc_rate, calc_valeur,  # PATCH 12\n'
    '                                   est_divergente, note_detail)',
    mk="est_divergente, note_detail", regex=True)
sub(p, r'            n1, n2 = float\(d1\.valeur\) if d1 else None, float\(d2\.valeur\) if d2 else None',
    '            n1 = note_detail(d1, ln.valeur_choisie) if d1 else None   # PATCH 12 : /5 normalisé\n'
    '            n2 = note_detail(d2, ln1.valeur_choisie) if d2 else None',
    mk="note_detail(d1, ln.valeur_choisie)", regex=True)
pycheck(p)

# ============================ 10. API NAVIGATION ============================
p = "backend/app/api/navigation.py"
sub(p, r'from sqlalchemy import func',
    'from sqlalchemy import case, func   # PATCH 12', mk="import case, func", regex=True)
AVG_OLD = "func.avg(CritereDetail.valeur)"
AVG_NEW = ("func.avg(case(\n"
           "            (CritereDetail.sens == 2,\n"
           "             func.coalesce(EvaluationLigne.valeur_choisie, CritereDetail.valeur)\n"
           "             * 5.0 / CritereDetail.valeur_max),\n"
           "            else_=func.coalesce(EvaluationLigne.valeur_choisie,\n"
           "                                 CritereDetail.valeur)))  # PATCH 12 : /5 normalisé")
c = rd(p)
if "PATCH 12 : /5 normalisé" in c:
    print("  SKIP  navigation.py :: moyennes déjà normalisées")
elif AVG_OLD in c:
    wr(p, c.replace(AVG_OLD, AVG_NEW))
    print("  OK    navigation.py :: moyennes normalisées")
else:
    print("  ??    navigation.py :: moyenne non trouvée (déjà traité ?)")
sub(p, r'return \[\{"id": s\.id, "matricule": s\.matricule, "nom": s\.full_name\} for s in salaries\]',
    'return [{"id": s.id, "matricule": s.matricule, "nom": s.full_name,\n'
    '            "section_id": s.section_id} for s in salaries]   # PATCH 12',
    mk='"section_id": s.section_id', regex=True)
append_block(p, '''

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
        ids = {user.id} | {s.id for s in collaborateurs_directs(db, user.id)} \\
              | {s.id for s in collaborateurs_indirects(db, user.id)}
        rows = (db.query(Section)
                .join(Salarie, Salarie.section_id == Section.id)
                .filter(Salarie.id.in_(ids)).distinct().all())
    return [{"id": x.id, "libelle": x.libelle} for x in sorted(rows, key=lambda z: z.libelle)]
''', "sections_perimetre")
pycheck(p)

# ========================= 11. API BENCH (réécrit) =========================
rewrite("backend/app/api/bench.py", '''# PATCH 12 — benchmark inter-sections (Admin) : agrégats par section,
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
''', "PATCH 12 — benchmark")

# ================================ FRONTEND ==================================
p = "frontend/src/components/DataTable.vue"
sub(p, r'\.dt-taille select \{\s*\n\s*margin-left: var\(--space-2\); height: 30px; border: 1px solid var\(--color-border\);',
    '.dt-taille select {\n'
    '  margin-left: var(--space-2); width: 72px; padding: 0 8px;   /* PATCH 12 : le chiffre était avalé */\n'
    '  height: 30px; border: 1px solid var(--color-border);',
    mk="le chiffre était avalé", regex=True)

# ------- HOTFIX : dédoublonner les imports .vue (erreur vite du matin : TourGuide x3) -------
def dedup_imports(p):
    c = rd(p)
    lines = c.split("\n"); seen = set(); out = []
    for l in lines:
        s = l.strip()
        if s.startswith("import "):
            if s in seen:
                print(f"  DEDUP {p} :: import supprimé :: {s}")
                continue
            seen.add(s)
        out.append(l)
    wr(p, "\n".join(out))

for p in ["frontend/src/App.vue"]:
    dedup_imports(p)

# ------------------------------ App.vue -------------------------------------
p = "frontend/src/App.vue"
sub(p, r'  if \(auth\.estN1 \|\| auth\.estN2 \|\| auth\.isAdmin\) \{\s*\n'
        r'\s*const camp = localStorage\.getItem\(\'campagneActive\'\)\s*\n'
        r'\s*if \(camp\) l\.push\(\{ to: \'/evaluations/\' \+ camp, label: \'EVALUATIONS\', key: \'evaluations\' \}\)',
    '  if ((auth.estN1 || auth.estN2 || auth.isAdmin) && !estMobile.value) {   // PATCH 12 : masqué mobile (via MON ESPACE)\n'
    "    const camp = localStorage.getItem('campagneActive')\n"
    "    if (camp) l.push({ to: '/evaluations/' + camp, label: 'EVALUATIONS', key: 'evaluations' })",
    mk="&& !estMobile.value) {   // PATCH 12", regex=True)
sub(p, r'      <button class="topbar-logout" title="Se déconnecter de l\'application" @click="deconnexion">\s*\n'
        r'\s*<LogOut :size="20" />\s*\n\s*</button>\s*\n',
    '<!-- PATCH 12 : bouton retiré — la déconnexion reste dans le menu hamburger -->\n',
    mk="PATCH 12 : bouton retiré", regex=True)

# --------------------------- ReferentielView.vue ----------------------------
p = "frontend/src/views/ReferentielView.vue"
sub(p, r"const ONGLETS = \['salaries', 'emplois', 'profils', 'criteres', 'sites',\s*\n"
        r"\s*'departements', 'sections', 'categories', 'postes'\]",
    "const ONGLETS = ['sites', 'departements', 'sections', 'emplois', 'categories',   // PATCH 12 : ordre demandé\n"
    "                 'postes', 'salaries', 'details_criteres', 'criteres', 'profils']",
    mk="const ONGLETS = ['sites'", regex=True)
sub(p, r"const LIBELLES = \{\s*\n"
        r"\s*salaries: 'Salariés', emplois: 'Emplois', profils: 'Profils', criteres: 'Critères',\s*\n"
        r"\s*sites: 'Sites', departements: 'Départements', sections: 'Sections',\s*\n"
        r"\s*categories: 'Catégories', postes: 'Postes',\s*\n\s*\}",
    "const LIBELLES = {   // PATCH 12\n"
    "  sites: 'Sites', departements: 'Départements', sections: 'Sections',\n"
    "  emplois: 'Emplois', categories: 'Catégories', postes: 'Postes',\n"
    "  salaries: 'Salariés', details_criteres: 'Détails Critères',\n"
    "  criteres: 'Critères', profils: 'Profils',\n"
    "}",
    mk="details_criteres: 'Détails Critères'", regex=True)
sub(p, r"const cles = \['sites', 'departements', 'sections', 'emplois', 'categories',\s*\n"
        r"\s*'postes', 'salaries', 'criteres', 'profils'\]",
    "const cles = ['sites', 'departements', 'sections', 'emplois', 'categories',\n"
    "                'postes', 'salaries', 'details_criteres', 'criteres', 'profils']  // PATCH 12",
    mk="'postes', 'salaries', 'details_criteres'", regex=True)
sub(p, r"  try \{ donnees\.value\[c\] = \(await api\.get\('/referentiel/' \+ c\)\)\.data \}",
    "  try { donnees.value[c] = (await api.get('/referentiel/' + (c === 'details_criteres' ? 'details-criteres' : c))).data }  // PATCH 12",
    mk="(c === 'details_criteres' ? 'details-criteres' : c)", regex=True)
sub(p, r"  try \{\s*\n\s*await api\.delete\('/referentiel/' \+ t \+ '/' \+ item\.id\)\s*\n",
    "  try {\n"
    "    await api.delete('/referentiel/' + (t === 'details_criteres' ? 'details-criteres' : t) + '/' + item.id)   // PATCH 12\n",
    mk="(t === 'details_criteres' ? 'details-criteres' : t)", regex=True)
# formulaire salarié : nature
sub(p, r"    date_embauche: '', email: '', n1_id: null, n2_id: null, hors_evaluation: false,\s*\n"
        r"\s*is_admin: false, is_active: true \}",
    "    date_embauche: '', email: '', n1_id: null, n2_id: null, hors_evaluation: false,\n"
    "    nature: 'Embauché', is_admin: false, is_active: true }   // PATCH 12 : nature",
    mk="nature: 'Embauché', is_admin", regex=True)
# ajouter() : onglet détails + editable critères
sub(p, r"  else if \(t === 'criteres'\) forme\.value = \{ t, code: '', libelle: '', actif: true, details: \[\] \}",
    "  else if (t === 'details_criteres') forme.value = { t, libelle_descriptif: '', valeur: 1, sens: 1, valeur_min: null, valeur_max: null, actif: true }   // PATCH 12\n"
    "  else if (t === 'criteres') forme.value = { t, code: '', libelle: '', actif: true, editable: false, details: [] }   // PATCH 12",
    mk="editable: false, details: []", regex=True)
# modifier() : champs détails enrichis
sub(p, r"  if \(t === 'criteres'\) f\.details = \(item\.details \|\| \[\]\)\.map\(function \(d\) \{\s*\n"
        r"\s*return \{ libelle_descriptif: d\.libelle_descriptif, valeur: d\.valeur, ordre: d\.ordre \} \}\)",
    "  if (t === 'criteres') f.details = (item.details || []).map(function (d) {   // PATCH 12\n"
    "    return { libelle_descriptif: d.libelle_descriptif, valeur: d.valeur, ordre: d.ordre,\n"
    "             sens: d.sens || 1, valeur_min: d.valeur_min, valeur_max: d.valeur_max, actif: d.actif !== false } })",
    mk="sens: d.sens || 1", regex=True)
# enregistrer() : branche details_criteres + editable + nature
sub(p, r"    \} else if \(f\.t === 'criteres'\) \{\s*\n"
        r"\s*const corps = \{ code: f\.code, libelle: f\.libelle, actif: f\.actif,\s*\n"
        r"\s*details: f\.details\.map\(function \(d, i\) \{\s*\n"
        r"\s*return \{ libelle_descriptif: d\.libelle_descriptif, valeur: Number\(d\.valeur\), ordre: i \} \}\) \}",
    "    } else if (f.t === 'details_criteres') {   // PATCH 12\n"
    "      const corps = { libelle_descriptif: f.libelle_descriptif, valeur: Number(f.valeur), ordre: 0,\n"
    "        sens: Number(f.sens || 1),\n"
    "        valeur_min: Number(f.sens) === 2 && f.valeur_min !== null ? Number(f.valeur_min) : null,\n"
    "        valeur_max: Number(f.sens) === 2 && f.valeur_max !== null ? Number(f.valeur_max) : null,\n"
    "        actif: !!f.actif }\n"
    "      if (modeEdition.value) await api.put('/referentiel/details-criteres/' + f.id, corps)\n"
    "      else await api.post('/referentiel/details-criteres', corps)\n"
    "    } else if (f.t === 'criteres') {\n"
    "      const corps = { code: f.code, libelle: f.libelle, actif: f.actif, editable: !!f.editable,   // PATCH 12\n"
    "        details: f.details.map(function (d, i) {\n"
    "          return { libelle_descriptif: d.libelle_descriptif, valeur: Number(d.valeur), ordre: i,\n"
    "            sens: Number(d.sens || 1),\n"
    "            valeur_min: Number(d.sens) === 2 && d.valeur_min != null ? Number(d.valeur_min) : null,\n"
    "            valeur_max: Number(d.sens) === 2 && d.valeur_max != null ? Number(d.valeur_max) : null,\n"
    "            actif: d.actif !== false } }) }",
    mk="f.t === 'details_criteres') {   // PATCH 12", regex=True)
sub(p, r"        is_admin: !!f\.is_admin, is_active: f\.is_active !== false \}",
    "        is_admin: !!f.is_admin, is_active: f.is_active !== false,\n"
    "        nature: f.nature || 'Embauché' }   // PATCH 12",
    mk="nature: f.nature || 'Embauché'", regex=True)
# colonnes : salariés + nature
sub(p, r"    \{ key: 'n2_nom', label: 'N\+2' \},\s*\n"
        r"\s*\{ key: 'hors_evaluation', label: 'Hors éval\.', format: v => \(v \? 'Oui' : 'Non'\), align: 'center' \},",
    "    { key: 'n2_nom', label: 'N+2' },\n"
    "    { key: 'nature', label: 'Nature' },   // PATCH 12\n"
    "    { key: 'hors_evaluation', label: 'Hors éval.', format: v => (v ? 'Oui' : 'Non'), align: 'center' },",
    mk="{ key: 'nature', label: 'Nature' }", regex=True)
# colonnes emplois : nb + actif
sub(p, r"    \{ key: 'profils_liste', label: 'Profils', keyFn: r => r \},\s*\n\s*ACTIONS,",
    "    { key: 'profils_liste', label: 'Profils', keyFn: r => r },\n"
    "    { key: 'nb_salaries', label: 'Nb Salariés', align: 'center', searchable: false },   // PATCH 12 (emplois)\n"
    "    { key: 'actif_aff', label: 'Actif', format: v => v, align: 'center', searchable: false },\n"
    "    ACTIONS,",
    mk="PATCH 12 (emplois)", regex=True)
# colonnes départements : nb + actif
sub(p, r"    \{ key: 'site_code', label: 'Site' \},\s*\n\s*ACTIONS,",
    "    { key: 'site_code', label: 'Site' },\n"
    "    { key: 'nb_salaries', label: 'Nb Salariés', align: 'center', searchable: false },   // PATCH 12 (départements)\n"
    "    { key: 'actif_aff', label: 'Actif', format: v => v, align: 'center', searchable: false },\n"
    "    ACTIONS,",
    mk="PATCH 12 (départements)", regex=True)
# colonnes sections : nb + actif
sub(p, r"    \{ key: 'dept_libelle', label: 'Département' \},\s*\n\s*ACTIONS,",
    "    { key: 'dept_libelle', label: 'Département' },\n"
    "    { key: 'nb_salaries', label: 'Nb Salariés', align: 'center', searchable: false },   // PATCH 12 (sections)\n"
    "    { key: 'actif_aff', label: 'Actif', format: v => v, align: 'center', searchable: false },\n"
    "    ACTIONS,",
    mk="PATCH 12 (sections)", regex=True)
# colonnes défaut (sites/catégories/postes) + onglet détails
sub(p, r"  return \[\s*\n"
        r"\s*\{ key: 'code', label: 'Code' \},\s*\n"
        r"\s*\{ key: 'libelle', label: 'Libellé' \},\s*\n"
        r"\s*ACTIONS,\s*\n\s*\]\s*\n\s*\}\)",
    "  if (t === 'details_criteres') return [   // PATCH 12\n"
    "    { key: 'libelle_descriptif', label: 'Descriptif' },\n"
    "    { key: 'type_aff', label: 'Type valeur' },\n"
    "    { key: 'val_aff', label: 'Valeur' },\n"
    "    { key: 'actif_aff', label: 'Actif', format: v => v, align: 'center', searchable: false },\n"
    "    ACTIONS,\n"
    "  ]\n"
    "  return [\n"
    "    { key: 'code', label: 'Code' },\n"
    "    { key: 'libelle', label: 'Libellé' },\n"
    "    { key: 'nb_salaries', label: 'Nb Salariés', align: 'center', searchable: false },   // PATCH 12 (défaut)\n"
    "    { key: 'actif_aff', label: 'Actif', format: v => v, align: 'center', searchable: false },\n"
    "    ACTIONS,\n"
    "  ]\n"
    "})",
    mk="PATCH 12 (défaut)", regex=True)
# lignes : salariés (admin_tri) / emplois / départements / sections / détails
sub(p, r"  if \(t === 'salaries'\) return base\.map\(s => \(\{\s*\n"
        r"\s*\.\.\.s, actif_aff: s\.is_active \? 'Actif' : 'Inactif',\s*\n\s*\}\)\)",
    "  if (t === 'salaries') return base.map(s => ({\n"
    "    ...s, actif_aff: s.is_active ? 'Actif' : 'Inactif',\n"
    "    admin_tri: s.is_admin ? 0 : 1,   // PATCH 12 : Admins en tête\n"
    "  }))",
    mk="admin_tri: s.is_admin", regex=True)
sub(p, r"  if \(t === 'emplois'\) return base\.map\(e => \(\{\s*\n"
        r"\s*\.\.\.e,\s*\n"
        r"\s*profils_liste: \(e\.profils \|\| \[\]\)\.map\(p => p\.libelle\)\.join\(' · '\),\s*\n\s*\}\)\)",
    "  if (t === 'emplois') return base.map(e => ({\n"
    "    ...e,\n"
    "    profils_liste: (e.profils || []).map(p => p.libelle).join(' · '),\n"
    "    nb_salaries: nbSalaries(e), actif_aff: e.actif !== false ? 'Actif' : 'Inactif',   // PATCH 12\n"
    "  }))",
    mk="nbSalaries(e)", regex=True)
sub(p, r"  if \(t === 'departements'\) return base\.map\(d => \(\{\s*\n"
        r"\s*\.\.\.d,\s*\n"
        r"\s*site_code: \(donnees\.value\.sites \|\| \[\]\)\.find\(s => s\.id === d\.site_id\)\?\.code \|\| '—',\s*\n\s*\}\)\)",
    "  if (t === 'departements') return base.map(d => ({\n"
    "    ...d,\n"
    "    site_code: (donnees.value.sites || []).find(s => s.id === d.site_id)?.code || '—',\n"
    "    nb_salaries: nbSalaries(d), actif_aff: d.actif !== false ? 'Actif' : 'Inactif',   // PATCH 12\n"
    "  }))",
    mk="nbSalaries(d)", regex=True)
sub(p, r"  if \(t === 'sections'\) return base\.map\(s => \(\{\s*\n"
        r"\s*\.\.\.s,\s*\n"
        r"\s*dept_libelle: libelleDepartement\(s\.departement_id\),\s*\n\s*\}\)\)",
    "  if (t === 'sections') return base.map(s => ({\n"
    "    ...s,\n"
    "    dept_libelle: libelleDepartement(s.departement_id),\n"
    "    nb_salaries: nbSalaries(s), actif_aff: s.actif !== false ? 'Actif' : 'Inactif',   // PATCH 12\n"
    "  }))",
    mk="nbSalaries(s)", regex=True)
sub(p, r"  if \(t === 'criteres'\) return base\.map\(c => \(\{ \.\.\.c, details_liste: ' ' \}\)\)",
    "  if (t === 'criteres') return base.map(c => ({ ...c, details_liste: ' ' }))\n"
    "  if (t === 'details_criteres') return base.map(d => ({   // PATCH 12\n"
    "    ...d,\n"
    "    type_aff: Number(d.sens) === 2 ? 'Intervalle' : 'Unique',\n"
    "    val_aff: Number(d.sens) === 2 ? (d.valeur_min + ' à ' + d.valeur_max) : d.valeur,\n"
    "    actif_aff: d.actif !== false ? 'Actif' : 'Inactif',\n"
    "  }))",
    mk="type_aff: Number(d.sens) === 2", regex=True)
sub(p, r"  return base\s*\n\s*\}\)\s*\n\s*function cleLigne",
    "  return base.map(r => ({ ...r, nb_salaries: nbSalaries(r),   // PATCH 12\n"
    "    actif_aff: r.actif !== false ? 'Actif' : 'Inactif' }))\n"
    "})\n"
    "function cleLigne",
    mk="nbSalaries(r)", regex=True)
# helpers : ajouterDetail enrichi, bibliothèque, nbSalaries, basculerActif
sub(p, r"function ajouterDetail\(\) \{ forme\.value\.details\.push\(\{ libelle_descriptif: '', valeur: 1, ordre: 0 \}\) \}",
    "function ajouterDetail() { forme.value.details.push({ libelle_descriptif: '', valeur: 1, ordre: 0,\n"
    "  sens: 1, valeur_min: null, valeur_max: null, actif: true }) }   // PATCH 12\n"
    "function ajouterDetailBiblio(ev) {   // PATCH 12 : depuis la bibliothèque Détails Critères\n"
    "  const b = (donnees.value.details_criteres || []).find(d => d.id === Number(ev.target.value))\n"
    "  if (b) forme.value.details.push({ libelle_descriptif: b.libelle_descriptif, valeur: b.valeur,\n"
    "    ordre: forme.value.details.length, sens: b.sens || 1, valeur_min: b.valeur_min,\n"
    "    valeur_max: b.valeur_max, actif: b.actif !== false })\n"
    "  ev.target.value = ''\n"
    "}\n"
    "function nbSalaries(r) {   // PATCH 12 : comptage des salariés rattachés\n"
    "  const cle = ({ sites: 'site_id', departements: 'departement_id', sections: 'section_id',\n"
    "    emplois: 'emploi_id', categories: 'categorie_id', postes: 'poste_id' })[onglet.value]\n"
    "  if (!cle) return 0\n"
    "  return (donnees.value.salaries || []).filter(s => s[cle] === r.id).length\n"
    "}\n"
    "async function basculerActif(t, row) {   // PATCH 12\n"
    "  erreur.value = ''\n"
    "  try {\n"
    "    await api.patch('/referentiel/' + t + '/' + row.id + '/toggle-active')\n"
    "    message.value = (row.actif === false ? 'Réactivé' : 'Désactivé') + ' : ' + (row.code || '')\n"
    "    await charger()\n"
    "  } catch (e) { erreur.value = e.response?.data?.detail || 'Action impossible.' }\n"
    "}",
    mk="async function basculerActif", regex=True)
# template : cellule actif avec toggle
sub(p, r"      <template #cell-actif_aff=\"\{ row \}\">\s*\n"
        r"\s*<span class=\"badge-statut\" :class=\"row\.is_active \? 'statut-vert' : 'statut-rouge'\">\s*\n"
        r"\s*\{\{ row\.is_active \? 'Actif' : 'Inactif' \}\}\s*\n"
        r"\s*</span>\s*\n"
        r"\s*</template>",
    '      <template #cell-actif_aff="{ row }">\n'
    "        <span v-if=\"onglet === 'salaries'\" class=\"badge-statut\" :class=\"row.is_active ? 'statut-vert' : 'statut-rouge'\">\n"
    "          {{ row.is_active ? 'Actif' : 'Inactif' }}\n"
    "        </span>\n"
    "        <button v-else class=\"badge-statut\" :class=\"row.actif !== false ? 'statut-vert' : 'statut-rouge'\"   <!-- PATCH 12 -->\n"
    "          :title=\"row.actif !== false ? 'Désactiver ce référentiel : plus pris en compte à la génération des fiches' : 'Réactiver ce référentiel'\"\n"
    "          @click=\"basculerActif(onglet, row)\">{{ row.actif !== false ? 'Actif' : 'Inactif' }}</button>\n"
    "      </template>",
    mk="basculerActif(onglet, row)", regex=True)
# DataTable : tri par défaut Admins
sub(p, r"    <DataTable :columns=\"colonnes\" :rows=\"lignes\" :row-key=\"cleLigne\"\s*\n"
        r"\s*:search-placeholder=",
    "    <DataTable :columns=\"colonnes\" :rows=\"lignes\" :row-key=\"cleLigne\"\n"
    "      :default-sort=\"onglet === 'salaries' ? { key: 'admin_tri', dir: 1 } : null\"   <!-- PATCH 12 : Admins en tête -->\n"
    "      :search-placeholder=",
    mk="key: 'admin_tri', dir: 1", regex=True)
# combobox salarié : CODE — LIBELLÉ (6 selects du formulaire salarié uniquement)
for var, col in [("s", "sites"), ("d", "departements"), ("s", "sections"),
                 ("e", "emplois"), ("c", "categories"), ("p", "postes")]:
    sub(p, r"<option v-for=\"" + var + r" in donnees\." + col + r"\" :key=\"" + var + r"\.id\" :value=\"" + var + r"\.id\">\{\{ " + var + r"\.code \}\}</option>",
        "<option v-for=\"" + var + "\" in donnees." + col + "\" :key=\"" + var + ".id\" :value=\"" + var + ".id\">{{ " + var + ".code }} — {{ " + var + ".libelle }}</option>   <!-- PATCH 12 -->",
        mk=f"combobox {col}", regex=True, optional=True, literal=False)
# formulaire salarié : champ NATURE (après PRÉNOMS)
sub(p, r"(<div class=\"field\"><label>PRÉNOMS</label><input v-model=\"forme\.prenoms\" title=\"Prénoms du salarié\" /></div>)",
    r'\1\n'
    r'          <div class="field"><label>NATURE</label>   <!-- PATCH 12 -->\n'
    r'            <select v-model="forme.nature" title="Nature du contrat : Embauché, Journalier, Contractuel, Stagiaire ou Apprenti">\n'
    r'              <option>Embauché</option><option>Journalier</option><option>Contractuel</option>\n'
    r'              <option>Stagiaire</option><option>Apprenti</option></select></div>',
    mk='v-model="forme.nature"', regex=True)
# formulaire critères : EDITABLE
sub(p, r"(<div class=\"field\"><label>ACTIF</label><input type=\"checkbox\" v-model=\"forme\.actif\" style=\"width:auto\" title=\"Critère actif \(utilisable dans les profils\)\" /></div>)",
    r'\1\n'
    r'          <div class="field"><label>EDITABLE (« A REMPLIR »)</label>   <!-- PATCH 12 -->\n'
    r'            <input type="checkbox" v-model="forme.editable" style="width:auto"\n'
    r'              title="Critère éditable : le libellé est pré-rempli avec les objectifs de la campagne précédente, le salarié peut l\'ajuster à l\'auto-évaluation" /></div>',
    mk='v-model="forme.editable"', regex=True)
# formulaire critères : type valeur par détail
sub(p, r"<input v-model=\"d\.libelle_descriptif\" placeholder=\"Libellé du détail\"\s*\n"
        r"\s*title=\"Texte proposé à la case dans le QCM\" />\s*\n"
        r"\s*<input v-model\.number=\"d\.valeur\" type=\"number\" step=\"0\.5\" style=\"width:80px\" title=\"Valeur cachée du détail \(contribute au score /5\)\" />",
    '<input v-model="d.libelle_descriptif" placeholder="Libellé du détail" style="flex:1"\n'
    '                 title="Texte proposé à la case dans le QCM" />\n'
    '              <select v-model.number="d.sens" style="width:104px"   <!-- PATCH 12 -->\n'
    '                title="Type de valeur : unique (un chiffre) ou intervalle (min-max, ajustable par étoiles)">\n'
    '                <option :value="1">Unique</option><option :value="2">Intervalle</option></select>\n'
    '              <template v-if="Number(d.sens) === 2">\n'
    '                <input v-model.number="d.valeur_min" type="number" step="0.5" style="width:60px" title="Borne minimale" placeholder="min" />\n'
    '                <input v-model.number="d.valeur_max" type="number" step="0.5" style="width:60px" title="Borne maximale" placeholder="max" />\n'
    '              </template>\n'
    '              <input v-else v-model.number="d.valeur" type="number" step="0.5" style="width:60px" title="Valeur cachée du détail (contribute au score /5)" />',
    mk='v-model.number="d.sens"', regex=True)
# bibliothèque dans le formulaire critères
sub(p, r"(<button class=\"btn ghost small\" type=\"button\" title=\"Ajouter une ligne de détail au QCM\" @click=\"ajouterDetail\">\+ Ajouter un détail</button>)",
    r'\1\n'
    r'            <select v-if="(donnees.details_criteres || []).some(x => !x.critere_id)"   <!-- PATCH 12 : bibliothèque -->\n'
    r'              style="margin-top:6px" title="Ajouter un détail existant depuis la bibliothèque Détails Critères"\n'
    r'              @change="ajouterDetailBiblio">\n'
    r'              <option value="">+ Depuis la bibliothèque…</option>\n'
    r'              <option v-for="b in (donnees.details_criteres || []).filter(x => !x.critere_id)" :key="b.id" :value="b.id">{{ b.libelle_descriptif }}</option>\n'
    r'            </select>',
    mk='@change="ajouterDetailBiblio">', regex=True)
# modale Détails Critères (formulaire standalone)
sub(p, r"        <template v-if=\"forme\.t === 'profils'\">",
    '        <template v-if="forme.t === \'details_criteres\'">   <!-- PATCH 12 -->\n'
    '          <div class="field"><label>DESCRIPTIF</label><input v-model="forme.libelle_descriptif" title="Libellé du détail proposé dans les QCM" /></div>\n'
    '          <div class="field"><label>TYPE VALEUR</label>\n'
    '            <select v-model.number="forme.sens" title="Valeur unique (un chiffre) ou valeur à intervalle (min-max, ajustable par étoiles)">\n'
    '              <option :value="1">Valeur unique</option><option :value="2">Valeur à intervalle</option></select></div>\n'
    '          <div class="field" v-if="Number(forme.sens) === 2"><label>MIN / MAX</label>\n'
    '            <div style="display:flex;gap:8px">\n'
    '              <input v-model.number="forme.valeur_min" type="number" step="0.5" title="Borne minimale de l\'intervalle" />\n'
    '              <input v-model.number="forme.valeur_max" type="number" step="0.5" title="Borne maximale de l\'intervalle" /></div></div>\n'
    '          <div class="field" v-else><label>VALEUR</label><input v-model.number="forme.valeur" type="number" step="0.5" title="Valeur cachée du détail" /></div>\n'
    '          <div class="field"><label>ACTIF</label><input type="checkbox" v-model="forme.actif" style="width:auto" title="Détail actif (proposé dans les QCM)" /></div>\n'
    '        </template>\n\n'
    '        <template v-if="forme.t === \'profils\'">',
    mk="forme.t === 'details_criteres'", regex=True)

# ------------------------- FicheEvaluationView.vue --------------------------
p = "frontend/src/views/FicheEvaluationView.vue"
sub(p, r"  reponse\.value = \{ detailId: null, commentaire: '' \}",
    "  reponse.value = { detailId: null, commentaire: '', etoiles: 1,   // PATCH 12\n"
    "    libelle: (ligne.libelle_perso || ligne.critere_libelle || '') }",
    mk="etoiles: 1", regex=True)
sub(p, r"const COLONNES = \[",
    "/* PATCH 12 — détail choisi + valeur étoile (intervalle min/milieu/max) */\n"
    "const detailChoisi = computed(() => (qcm.value?.ligne.details || []).find(d => d.id === reponse.value.detailId) || null)\n"
    "const valeurEtoile = computed(() => {\n"
    "  const d = detailChoisi.value\n"
    "  if (!d || Number(d.sens) !== 2) return null\n"
    "  const min = Number(d.valeur_min ?? d.valeur), max = Number(d.valeur_max ?? d.valeur)\n"
    "  return [min, (min + max) / 2, max][reponse.value.etoiles - 1]\n"
    "})\n"
    "const COLONNES = [",
    mk="const detailChoisi", regex=True)
sub(p, r"async function validerQcm\(\) \{",
    "async function validerQcm() {\n"
    "  // PATCH 12 — critère editable : le salarié (N) peut préciser le libellé de son objectif\n"
    "  if (qcm.value.etape === 'N' && qcm.value.ligne.editable\n"
    "      && (reponse.value.libelle || '').trim() !== (qcm.value.ligne.critere_libelle || '').trim()) {\n"
    "    try { await api.post('/evaluations/' + route.params.evaluationId + '/libelle-critere',\n"
    "      { critere_id: qcm.value.ligne.critere_id, libelle: reponse.value.libelle.trim() }) }\n"
    "    catch (e) { erreur.value = e.response?.data?.detail; return }\n"
    "  }",
    mk="'/libelle-critere'", regex=True)
sub(p, r"      critere_detail_id: reponse\.value\.detailId,\s*\n"
        r"\s*commentaire: reponse\.value\.commentaire\.trim\(\),\s*\n\s*\}\)",
    "      critere_detail_id: reponse.value.detailId,\n"
    "      commentaire: reponse.value.commentaire.trim(),\n"
    "      valeur_choisie: valeurEtoile.value,   // PATCH 12 : étoiles intervalle\n"
    "    })",
    mk="valeur_choisie: valeurEtoile.value", regex=True)
sub(p, r"(<p class=\"qcm-consigne\">Cochez la description qui correspond le mieux à vos aptitudes\.\s*\n"
        r"\s*Il n'y a pas de bonne ou mauvaise réponse\.</p>)",
    r'\1\n'
    r'        <!-- PATCH 12 : libellé editable (objectif « A REMPLIR ») -->\n'
    r'        <div v-if="qcm.etape === \'N\' && qcm.ligne.editable" class="qcm-libelle-edit">\n'
    r'          <label>LIBELLÉ DU CRITÈRE (à renseigner)</label>\n'
    r'          <input v-model="reponse.libelle"\n'
    r'            title="Libellé de votre objectif — pré-rempli depuis la campagne précédente si disponible" />\n'
    r'        </div>',
    mk='class="qcm-libelle-edit"', regex=True)
sub(p, r"(<div class=\"qcm-commentaire\">)",
    '        <!-- PATCH 12 : étoiles sur les détails à intervalle (min / milieu / max) -->\n'
    '        <div v-if="detailChoisi && Number(detailChoisi.sens) === 2" class="qcm-etoiles">\n'
    '          <label>Degré d\'appréciation — {{ detailChoisi.valeur_min }} à {{ detailChoisi.valeur_max }}\n'
    '            (1 étoile = minimum, 3 étoiles = maximum de l\'intervalle)</label>\n'
    '          <div class="etoiles">\n'
    '            <button v-for="n in 3" :key="n" type="button" class="etoile-btn"\n'
    '              :class="{ pleine: n <= reponse.etoiles }"\n'
    '              :title="n + \' étoile(s)\'" @click="reponse.etoiles = n">★</button>\n'
    '          </div>\n'
    '        </div>\n\n'
    r'\1',
    mk='class="qcm-etoiles"', regex=True)
sub(p, r"(/\* ---------- PATCH 8 — mobile : cartes empilées ---------- \*/)",
    '/* ---------- PATCH 12 : étoiles + libellé editable ---------- */\n'
    '.qcm-etoiles { margin-bottom: var(--space-6); }\n'
    '.qcm-etoiles label { font-size: var(--font-size-xs); font-weight: 800; letter-spacing: .5px; margin-bottom: var(--space-1); }\n'
    '.etoiles { display: flex; gap: 4px; }\n'
    '.etoile-btn { font-size: 26px; line-height: 1; border: none; background: none; cursor: pointer;\n'
    '  color: var(--color-border); padding: 2px 4px; }\n'
    '.etoile-btn.pleine { color: #f59e0b; }\n'
    '.qcm-libelle-edit { margin-bottom: var(--space-4); }\n'
    '\n'
    r'\1',
    mk=".etoile-btn.pleine", regex=True)

# --------------------------- BenchmarkView (réécrit) ------------------------
rewrite("frontend/src/views/BenchmarkView.vue", '''<!-- PATCH 12 — benchmark inter-sections (Admin) : TOUTES les sections affichées
     (plus d'anonymisation), recherche + tri via DataTable. -->
<script setup>
import { onMounted, ref } from 'vue'
import api from '../api/client'
import DataTable from '../components/DataTable.vue'

const sections = ref([])
const erreur = ref('')

async function charger() {
  try { sections.value = (await api.get('/bench/sections')).data }
  catch (e) { erreur.value = e.response?.data?.detail || 'Chargement impossible.' }
}
onMounted(charger)

function barre(v) { return { height: '100%', width: (v || 0) + '%', transition: 'width .3s' } }
const COLONNES = [
  { key: 'section', label: 'Section' },
  { key: 'nb_fiches', label: 'Fiches', align: 'center' },
  { key: 'pct_n', label: 'Auto-éval. clôturées (%)', align: 'center' },
  { key: 'pct_n1', label: 'Éval. N+1 clôturées (%)', align: 'center' },
  { key: 'pct_approuvees', label: 'Approuvées (%)', align: 'center' },
]
</script>

<template>
  <div>
    <h3>BENCHMARK INTER-SECTIONS</h3>
    <p class="muted">Agrégats sur toutes les fiches évaluées : avancement par section
      (auto-évaluations, évaluations N+1, approbations).</p>
    <div v-if="erreur" class="error">{{ erreur }}</div>
    <DataTable :columns="COLONNES" :rows="sections" :row-key="'section'"
      search-placeholder="Rechercher une section…">
      <template #cell-pct_n="{ row }">
        <div class="barre-g"><div :style="barre(row.pct_n)" style="background: var(--color-brand)"></div></div>{{ row.pct_n }} %
      </template>
      <template #cell-pct_n1="{ row }">
        <div class="barre-g"><div :style="barre(row.pct_n1)" style="background: var(--color-orange)"></div></div>{{ row.pct_n1 }} %
      </template>
      <template #cell-pct_approuvees="{ row }">
        <div class="barre-g"><div :style="barre(row.pct_approuvees)" style="background: var(--color-vert)"></div></div>{{ row.pct_approuvees }} %
      </template>
    </DataTable>
    <div v-if="!sections.length && !erreur" class="muted">Aucune donnée à comparer pour l'instant.</div>
  </div>
</template>

<style scoped>
h3 { font-size: 13px; color: var(--color-brand-dark); margin-bottom: 8px; }
.muted { color: var(--color-text-muted); font-size: 12px; }
.barre-g { display: inline-block; vertical-align: middle; width: 120px; height: 8px; background: var(--color-border); border-radius: 4px; overflow: hidden; margin-right: 8px; }
</style>
''', "BENCHMARK INTER-SECTIONS</h3>")

# ----------------------------- NavigationView.vue ---------------------------
p = "frontend/src/views/NavigationView.vue"
sub(p, r"import \{ onMounted, ref \} from 'vue'",
    "import { computed, onMounted, ref } from 'vue'   // PATCH 12", mk="import { computed, onMounted, ref }", regex=True)
sub(p, r"const criteres = ref\(\[\]\)",
    "const criteres = ref([])\n"
    "const sections = ref([])   // PATCH 12\n"
    "const filtreSection = ref('')   // PATCH 12",
    mk="const filtreSection = ref('')", regex=True)
sub(p, r"  salaries\.value = \(await api\.get\('/navigation/salaries'\)\)\.data",
    "  salaries.value = (await api.get('/navigation/salaries')).data\n"
    "  try { sections.value = (await api.get('/navigation/sections')).data } catch { sections.value = [] }   // PATCH 12",
    mk="/navigation/sections')", regex=True)
sub(p, r"async function lancerBenchmark\(\) \{",
    "const salariesAffiches = computed(() => filtreSection.value   // PATCH 12\n"
    "  ? salaries.value.filter(s => s.section_id === filtreSection.value)\n"
    "  : salaries.value)\n"
    "function surFiltreSection() {   // PATCH 12\n"
    "  if (!salariesAffiches.value.some(s => s.id === salarieId.value)) {\n"
    "    salarieId.value = salariesAffiches.value[0]?.id || ''\n"
    "    afficher()\n"
    "  }\n"
    "}\n"
    "async function lancerBenchmark() {",
    mk="const salariesAffiches", regex=True)
sub(p, r"(<select v-model=\"salarieId\" @change=\"afficher\" class=\"sel-large\"[\s\S]*?</select>)",
    r'\1\n'
    '      <select v-model="filtreSection" class="sel-large" @change="surFiltreSection"   <!-- PATCH 12 -->\n'
    '        title="Filtrer par section (sections de votre périmètre)">\n'
    '        <option value="">— Toutes les sections —</option>\n'
    '        <option v-for="sc in sections" :key="sc.id" :value="sc.id">{{ sc.libelle }}</option>\n'
    '      </select>',
    mk='@change="surFiltreSection"', regex=True)
sub(p, r"        <option v-for=\"s in salaries\" :key=\"s\.id\" :value=\"s\.id\">\{\{ s\.matricule \}\} – \{\{ s\.nom \}\}</option>",
    '        <option v-for="s in salariesAffiches" :key="s.id" :value="s.id">{{ s.matricule }} – {{ s.nom }}</option>   <!-- PATCH 12 -->',
    mk='v-for="s in salariesAffiches"', regex=True)

print("\n=== Édition des fichiers terminée sans erreur ===")
PYEOF
[ $? -ne 0 ] && { echo "ÉCHEC de l'édition — arrêt avant la migration."; exit 1; }

# ============================================================================
# MIGRATION DB (idempotente, via le venv du backend)
# ============================================================================
echo "=== PATCH 12 — migration base de données ==="
mkdir -p backend/scripts
cat > backend/scripts/patch12_migration.py <<'MIGEOF'
# PATCH 12 — migration DB (idempotente). Lancer depuis backend/ avec le venv :
#   .venv/bin/python scripts/patch12_migration.py
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
try:
    from app.core.database import engine
except ImportError:  # secours
    from app.core.database import SessionLocal
    engine = SessionLocal.kw["bind"]
from sqlalchemy import text

SQL = [
    "ALTER TABLE sites ADD COLUMN IF NOT EXISTS actif boolean NOT NULL DEFAULT true",
    "ALTER TABLE departements ADD COLUMN IF NOT EXISTS actif boolean NOT NULL DEFAULT true",
    "ALTER TABLE sections ADD COLUMN IF NOT EXISTS actif boolean NOT NULL DEFAULT true",
    "ALTER TABLE emplois ADD COLUMN IF NOT EXISTS actif boolean NOT NULL DEFAULT true",
    "ALTER TABLE categories ADD COLUMN IF NOT EXISTS actif boolean NOT NULL DEFAULT true",
    "ALTER TABLE postes ADD COLUMN IF NOT EXISTS actif boolean NOT NULL DEFAULT true",
    "ALTER TABLE criteres ADD COLUMN IF NOT EXISTS editable boolean NOT NULL DEFAULT false",
    "ALTER TABLE critere_details ADD COLUMN IF NOT EXISTS sens smallint NOT NULL DEFAULT 1",
    "ALTER TABLE critere_details ADD COLUMN IF NOT EXISTS valeur_min numeric(5,2)",
    "ALTER TABLE critere_details ADD COLUMN IF NOT EXISTS valeur_max numeric(5,2)",
    "ALTER TABLE critere_details ADD COLUMN IF NOT EXISTS actif boolean NOT NULL DEFAULT true",
    "ALTER TABLE critere_details ALTER COLUMN critere_id DROP NOT NULL",
    "ALTER TABLE salaries ADD COLUMN IF NOT EXISTS nature varchar(20) NOT NULL DEFAULT 'Embauché'",
    "ALTER TABLE evaluation_lignes ADD COLUMN IF NOT EXISTS valeur_choisie numeric(5,2)",
    """CREATE TABLE IF NOT EXISTS evaluation_criteres (
        id serial PRIMARY KEY,
        evaluation_id integer NOT NULL REFERENCES evaluations(id),
        critere_id integer NOT NULL REFERENCES criteres(id),
        libelle varchar(300) NOT NULL,
        UNIQUE (evaluation_id, critere_id)
    )""",
    # Détails à intervalle (legacy SENS=2) : 7-9 / 10-12 / 13-15 / 16-18 / 19-20
    "UPDATE critere_details SET sens=2, valeur_min=7,  valeur_max=9  WHERE sens=1 AND lower(trim(libelle_descriptif))='très insatisfaisant'",
    "UPDATE critere_details SET sens=2, valeur_min=10, valeur_max=12 WHERE sens=1 AND lower(trim(libelle_descriptif))='a améliorer'",
    "UPDATE critere_details SET sens=2, valeur_min=13, valeur_max=15 WHERE sens=1 AND lower(trim(libelle_descriptif))='satisfaisant'",
    "UPDATE critere_details SET sens=2, valeur_min=16, valeur_max=18 WHERE sens=1 AND lower(trim(libelle_descriptif))='excellent'",
    "UPDATE critere_details SET sens=2, valeur_min=19, valeur_max=20 WHERE sens=1 AND lower(trim(libelle_descriptif))='top performer'",
]
with engine.begin() as con:
    for s in SQL:
        con.execute(text(s))
print("MIGRATION PATCH 12 OK (actif x6, editable, sens/min/max/actif détails, nature, "
      "valeur_choisie, table evaluation_criteres, intervalles 7-9/10-12/13-15/16-18/19-20).")
MIGEOF

VENV=""
for c in backend/.venv/bin/python .venv/bin/python backend/venv/bin/python; do
  [ -x "$c" ] && VENV="$c" && break
done
if [ -n "$VENV" ]; then
  ( cd backend && "$VENV" scripts/patch12_migration.py ) \
    && echo "=== MIGRATION OK ===" \
    || echo "⚠ Migration en échec — vérifie le venv/postgres puis relance : cd backend && .venv/bin/python scripts/patch12_migration.py"
else
  echo "⚠ venv introuvable — lance la migration à la main :"
  echo "   cd backend && .venv/bin/python scripts/patch12_migration.py"
fi

echo ""
echo "=== PATCH 12 terminé. Relance backend (uvicorn --port 8003) + frontend (vite), puis recette. ==="