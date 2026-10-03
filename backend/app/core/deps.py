# 2026-10-02 — dépendances FastAPI : utilisateur courant + gardes de rôle.
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import decode_access_token
from app.models.rating import Salarie

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")


def get_current_user(
    token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)
) -> Salarie:
    credentials_exc = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Session invalide ou expirée.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    matricule = decode_access_token(token)
    if not matricule:
        raise credentials_exc
    user = db.query(Salarie).filter(Salarie.matricule == matricule).first()
    if not user or not user.is_active:
        raise credentials_exc
    return user


def require_admin(user: Salarie = Depends(get_current_user)) -> Salarie:
    if not user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Réservé aux administrateurs.",
        )
    return user
