# 2026-10-05 PATCH 12 — schémas du référentiel (M5) : actif, editable,
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
