# 2026-10-02 — schémas du référentiel (M5).
from datetime import date
from pydantic import BaseModel, Field


class SimpleRef(BaseModel):
    id: int
    code: str
    libelle: str
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
    valeur: float = Field(ge=0, le=10)
    ordre: int = 0


class CritereDetailOut(BaseModel):
    id: int
    libelle_descriptif: str
    valeur: float
    ordre: int
    model_config = {"from_attributes": True}


class CritereOut(BaseModel):
    id: int
    code: str
    libelle: str
    actif: bool
    details: list[CritereDetailOut] = []
    model_config = {"from_attributes": True}


class CritereIn(BaseModel):
    code: str
    libelle: str
    actif: bool = True
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
    hors_evaluation: bool = False
    is_admin: bool = False
    is_active: bool = True


class SalarieOut(SalarieIn):
    id: int
    n1_nom: str | None = None
    model_config = {"from_attributes": True}
