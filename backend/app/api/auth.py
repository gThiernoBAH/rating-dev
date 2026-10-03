# 2026-10-02 — routes d'authentification : login matricule+mot de passe,
# throttle 5 échecs / 15 min (§5), /me avec rôles relationnels.
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.core.security import create_access_token, verify_password
from app.core.throttle import is_locked, register_failure, reset_failures
from app.models.rating import Salarie
from app.schemas.auth import LoginRequest, MeResponse, TokenResponse
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
    if not user or not verify_password(payload.password, user.password_hash):
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
