# 2026-10-02 — journal d'audit renforcé (annexe A.3) : toute écriture tracée.
from sqlalchemy.orm import Session

from app.models.rating import AuditLog


def log_action(
    db: Session,
    *,
    auteur_id: int | None,
    action: str,
    table_cible: str,
    enregistrement_id: int | None = None,
    avant: dict | None = None,
    apres: dict | None = None,
    justification: str | None = None,
) -> None:
    db.add(
        AuditLog(
            auteur_id=auteur_id,
            action=action,
            table_cible=table_cible,
            enregistrement_id=enregistrement_id,
            avant=avant,
            apres=apres,
            justification=justification,
        )
    )
