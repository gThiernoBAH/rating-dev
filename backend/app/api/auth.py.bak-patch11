# 2026-10-02 — routes d'authentification : login matricule+mot de passe,
# throttle 5 échecs / 15 min (§5), /me avec rôles relationnels.
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.core.security import create_access_token, verify_password, hash_password
from app.core.throttle import is_locked, register_failure, reset_failures
from app.models.rating import Salarie
from app.schemas.auth import LoginRequest, MeResponse, TokenResponse, DefinirMdpIn, MessageResponse
from app.services.hierarchie import (
    a_des_collaborateurs_directs, a_des_collaborateurs_indirects,
)

router = APIRouter(prefix="/api/auth", tags=["Authentification"])


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)):
    matricule = payload.matricule.strip()

    lock = is_locked(matricule)
    if lock > 0:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Trop de tentatives. Réessayez dans {lock} secondes.",
        )

    user = db.query(Salarie).filter(Salarie.matricule == matricule).first()
    premiere_connexion = bool(user and not user.password_hash)
    if not user or (not premiere_connexion and not verify_password(payload.password, user.password_hash)):
        register_failure(matricule)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Matricule ou mot de passe incorrect.",
        )
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Compte désactivé. Contactez l'administrateur.",
        )

    reset_failures(matricule)
    if premiere_connexion:
        user.must_change_password = True
        db.commit()
    return TokenResponse(
        access_token=create_access_token(user.matricule),
        must_change_password=user.must_change_password,
    )


@router.get("/me", response_model=MeResponse)
def me(user: Salarie = Depends(get_current_user), db: Session = Depends(get_db)):
    return MeResponse(
        matricule=user.matricule,
        nom=user.nom,
        prenoms=user.prenoms,
        is_admin=user.is_admin,
        hors_evaluation=user.hors_evaluation,
        est_n1=a_des_collaborateurs_directs(db, user.id),
        est_n2=a_des_collaborateurs_indirects(db, user.id),
    )


@router.post("/definir-mot-de-passe", response_model=MessageResponse)
def definir_mot_de_passe(payload: DefinirMdpIn, db: Session = Depends(get_db),
                         user: Salarie = Depends(get_current_user)):
    """Première connexion (ou changement demandé) : le salarié crée SON mot de
    passe. Minimum 6 caractères. Une fois défini, le mot de passe vide ne
    permet plus rien (le hash existe)."""
    mdp = payload.nouveau.strip()
    if len(mdp) < 6:
        raise HTTPException(422, "Le mot de passe doit contenir au moins 6 caractères.")
    user.password_hash = hash_password(mdp)
    user.must_change_password = False
    db.commit()
    return MessageResponse(detail="Mot de passe créé. Vous pouvez utiliser l'application.")
