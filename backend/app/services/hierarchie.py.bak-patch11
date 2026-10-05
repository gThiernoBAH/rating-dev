# 2026-10-02 — hiérarchie relationnelle : N+1 / N+2 déduits, jamais saisis (§3, §5).
from sqlalchemy.orm import Session

from app.models.rating import Salarie


def collaborateurs_directs(db: Session, salarie_id: int) -> list[Salarie]:
    return (
        db.query(Salarie)
        .filter(Salarie.n1_id == salarie_id, Salarie.is_active.is_(True))
        .all()
    )


def collaborateurs_indirects(db: Session, salarie_id: int) -> list[Salarie]:
    """N+2 = collaborateurs des collaborateurs directs."""
    directs = collaborateurs_directs(db, salarie_id)
    if not directs:
        return []
    ids = [s.id for s in directs]
    return (
        db.query(Salarie)
        .filter(Salarie.n1_id.in_(ids), Salarie.is_active.is_(True))
        .all()
    )


def a_des_collaborateurs_directs(db: Session, salarie_id: int) -> bool:
    return (
        db.query(Salarie.id)
        .filter(Salarie.n1_id == salarie_id, Salarie.is_active.is_(True))
        .first()
        is not None
    )


def a_des_collaborateurs_indirects(db: Session, salarie_id: int) -> bool:
    return len(collaborateurs_indirects(db, salarie_id)) > 0
