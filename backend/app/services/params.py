# 2026-10-02 — lecture des paramètres (jamais de valeur en dur dans le code).
from sqlalchemy.orm import Session

from app.models.rating import Param


def get_param(db: Session, cle: str, defaut: str = "") -> str:
    p = db.query(Param).get(cle)
    return p.valeur if p else defaut


def get_paliers(db: Session) -> list[tuple[float, float, str]]:
    """Paliers d'appréciation paramétrables : [(borne_basse, borne_haute, libelle), ...]"""
    paliers = []
    for cle in ("palier_insuffisant", "palier_moyen", "palier_bien", "palier_excellent"):
        brut = get_param(db, cle)
        if not brut:
            continue
        parties = brut.split(";", 2)
        if len(parties) == 3:
            paliers.append((float(parties[0]), float(parties[1]), parties[2]))
    paliers.sort()
    return paliers


def appreciation(db: Session, note: float | None) -> str | None:
    if note is None:
        return None
    for bas, haut, libelle in get_paliers(db):
        if bas <= note < haut:
            return libelle
    return None
