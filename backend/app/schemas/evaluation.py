# 2026-10-02 — schémas fiche d'évaluation (M4), notations (M4bis), navigation.
from datetime import date, datetime
from pydantic import BaseModel, Field


class FicheEntete(BaseModel):
    id: int
    numero: str
    matricule: str
    nom: str
    emploi: str | None = None
    poste: str | None = None
    departement: str | None = None
    section: str | None = None
    categorie: str | None = None
    anciennete_annees: int | None = None
    n1_nom: str | None = None
    n1_poste: str | None = None
    date_evaluation: date | None = None
    statut_n: str
    statut_n1: str
    statut_n2: str
    statut_global: str
    commentaire_global: str | None = None


class LigneFiche(BaseModel):
    profil_id: int
    profil_libelle: str
    critere_id: int
    critere_libelle: str
    ordre: int
    coefficient: float
    editable: bool = False                      # PATCH 12 : libellé « A REMPLIR »
    libelle_perso: str | None = None              # PATCH 12 : pré-rempli objectifs N-1
    # étape N
    auto_libelle: str | None = None       # libellé descriptif coché (pas une note visible)
    commentaire_n: str | None = None
    # étape N+1
    eval_libelle: str | None = None
    commentaire_n1: str | None = None
    details: list[dict] = []              # détails cochables du QCM (libellé + id)


class FicheDetail(BaseModel):
    entete: FicheEntete
    profils: list[LigneFiche] = []
    mon_etape: str | None = None          # 'N' | 'N+1' | 'N+2' | 'ADMIN' selon le rôle


class QcmIn(BaseModel):
    etape: str = Field(pattern="^(N|N\\+1)$")
    profil_id: int
    critere_id: int
    critere_detail_id: int
    valeur_choisie: float | None = None        # PATCH 12 : étoiles intervalle
    commentaire: str = Field(min_length=3)  # obligatoire dès qu'une case est cochée


class ClotureIn(BaseModel):
    etape: str = Field(pattern="^(N|N\\+1)$")


class ApprobationIn(BaseModel):
    decision: str = Field(pattern="^(Approuvé|Approuvé avec réserves)$")
    observation: str | None = None


class CommentaireGlobalIn(BaseModel):
    commentaire_global: str = Field(min_length=3)


class NotationLigne(BaseModel):
    profil_libelle: str
    critere_libelle: str
    coefficient: float
    note1: float | None = None
    note2: float | None = None
    valeur1: float | None = None
    valeur2: float | None = None
    commentaire_n: str | None = None
    commentaire_n1: str | None = None
    rate1: int | None = None
    rate2: int | None = None
    divergence: bool = False


class NotationProfil(BaseModel):
    profil_libelle: str
    lignes: list[NotationLigne]
    total_coeff: float
    total_valeur1: float | None
    total_valeur2: float | None
    note_globale1: float | None
    note_globale2: float | None


class NotationFiche(BaseModel):
    entete: FicheEntete
    profils: list[NotationProfil]
    note_globale_n: float | None
    note_globale_n1: float | None
    appreciation_n: str | None
    appreciation_n1: str | None
    approbation: dict | None = None
