# 2026-10-02 — bcrypt + JWT (mot de passe jamais stocké en clair, TTL 12 h)
from datetime import datetime, timedelta, timezone

from jose import JWTError, jwt
from passlib.context import CryptContext

from app.core.settings import get_settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
ALGORITHM = "HS256"


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str | None) -> bool:
    if not hashed:
        return False
    return pwd_context.verify(plain, hashed)


def create_access_token(matricule: str) -> str:
    settings = get_settings()
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.ACCESS_TOKEN_TTL_MINUTES
    )
    payload = {"sub": matricule, "exp": expire}
    return jwt.encode(payload, settings.AUTH_SECRET_KEY, algorithm=ALGORITHM)


def decode_access_token(token: str) -> str | None:
    """Retourne le matricule si le jeton est valide, sinon None."""
    try:
        payload = jwt.decode(
            token, get_settings().AUTH_SECRET_KEY, algorithms=[ALGORITHM]
        )
        return payload.get("sub")
    except JWTError:
        return None
