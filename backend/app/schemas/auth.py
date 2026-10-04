# 2026-10-02 — schémas d'authentification (login matricule, jeton 12 h).
from pydantic import BaseModel, Field


class LoginRequest(BaseModel):
    matricule: str = Field(min_length=1)
    password: str = Field(min_length=1)


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    must_change_password: bool = False


class MeResponse(BaseModel):
    matricule: str
    nom: str
    prenoms: str | None = None
    is_admin: bool
    hors_evaluation: bool
    # rôles relationnels (§5) : rempli par le service selon la hiérarchie
    est_n1: bool = False    # a au moins un collaborateur direct
    est_n2: bool = False    # a au moins un collaborateur indirect


class DefinirMdpIn(BaseModel):
    nouveau: str


class MessageResponse(BaseModel):
    detail: str
