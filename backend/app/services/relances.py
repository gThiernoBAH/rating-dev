# PATCH 10 — moteur de relances : retardataires d'une campagne Ouverte,
# notification cloche (anti-spam : 1 relance max / fiche / destinataire / 24 h).
from datetime import datetime, timedelta

from sqlalchemy.orm import Session

from app.models.rating import Evaluation, Notification, Salarie


def retardataires(db: Session, campagne) -> dict:
    """Classifie : 'N' (auto-éval non clôturée), 'N+1' (éval non clôturée),
    'N+2' (approbation en attente). Retourne (fiche, salarié, responsable_id)."""
    out = {"N": [], "N+1": [], "N+2": []}
    for e in db.query(Evaluation).filter(Evaluation.campagne_id == campagne.id).all():
        s = db.query(Salarie).get(e.salarie_id)
        if not s:
            continue
        n1s = db.query(Salarie).get(s.n1_id) if s.n1_id else None
        n2_id = getattr(s, "n2_id", None) or (n1s.n1_id if n1s else None)
        if e.statut_n == "En cours":
            out["N"].append((e, s, s.id))
        elif e.statut_n1 == "En cours":
            out["N+1"].append((e, s, s.n1_id))
        elif e.statut_global != "Approuvé":
            out["N+2"].append((e, s, n2_id))
    return out


def _deja_relance(db: Session, salarie_id: int, numero: str) -> bool:
    limite = datetime.now() - timedelta(hours=24)
    return (
        db.query(Notification.id)
        .filter(
            Notification.salarie_id == salarie_id,
            Notification.titre.like("RELANCE —%"),
            Notification.message.like("%" + numero + "%"),
            Notification.horodatage >= limite,
        )
        .first()
        is not None
    )


def envoyer_relances(db: Session, campagne) -> dict:
    ret = retardataires(db, campagne)
    notifiees = deja_relancees = 0
    for etape, fiches in ret.items():
        for e, s, resp_id in fiches:
            if not resp_id:
                continue
            if _deja_relance(db, resp_id, e.numero):
                deja_relancees += 1
                continue
            db.add(Notification(
                salarie_id=resp_id,
                titre=f"RELANCE — {campagne.nom}",
                message=(
                    f"Votre étape {etape} est en attente : "
                    f"fiche n° {e.numero} de {s.full_name}. "
                    f"Merci de la traiter avant la clôture de la campagne."
                ),
            ))
            notifiees += 1
    db.commit()
    return {
        "notifiees": notifiees, "deja_relancees": deja_relancees,
        "n": len(ret["N"]), "n1": len(ret["N+1"]), "n2": len(ret["N+2"]),
    }
