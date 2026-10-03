# 2026-10-02 — schémas campagnes (M6) + rapports de génération.
from datetime import date
from pydantic import BaseModel, Field


class CampagneIn(BaseModel):
    nom: str = Field(min_length=3)
    exercice: int
    date_ouverture: date
    date_cloture: date


class CampagneOut(BaseModel):
    id: int
    nom: str
    exercice: int
    date_ouverture: date | None
    date_cloture: date | None
    statut: str
    model_config = {"from_attributes": True}


class GenerationIn(BaseModel):
    familles: list[int] = Field(min_length=1)   # sous-ensemble de [1,2,3] coché par l'Admin
    rattrapage: bool = False                     # True = uniquement les fiches manquantes


class GenerationReport(BaseModel):
    creees: int = 0
    deja_existantes: int = 0
    hors_evaluation: int = 0
    sans_n1: list[str] = []       # matricules signalés
    cutoff_exclus: int = 0
