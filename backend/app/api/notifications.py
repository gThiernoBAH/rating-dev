# 2026-10-02 — notifications (§11) : cloche (toujours), mail + Telegram côté
# service dédié. WhatsApp prévu/désactivé. Événements de séquencement (annexe A.4).
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.rating import Notification, Salarie
from app.schemas.common import MessageResponse

router = APIRouter(prefix="/api/notifications", tags=["Notifications"])


@router.get("")
def mes_notifications(db: Session = Depends(get_db),
                     user: Salarie = Depends(get_current_user)):
    notifs = db.query(Notification).filter(
        Notification.salarie_id == user.id).order_by(
        Notification.horodatage.desc()).limit(50).all()
    return [{"id": n.id, "titre": n.titre, "message": n.message, "lu": n.lu,
             "horodatage": n.horodatage.isoformat()} for n in notifs]


@router.get("/non-lues")
def count_non_lues(db: Session = Depends(get_db),
                   user: Salarie = Depends(get_current_user)):
    nb = db.query(Notification).filter(
        Notification.salarie_id == user.id,
        Notification.lu.is_(False)).count()
    return {"non_lues": nb}


@router.post("/{notification_id}/lire", response_model=MessageResponse)
def marquer_lue(notification_id: int, db: Session = Depends(get_db),
                user: Salarie = Depends(get_current_user)):
    n = db.query(Notification).get(notification_id)
    if not n or n.salarie_id != user.id:
        return MessageResponse(detail="Introuvable.")
    n.lu = True
    db.commit()
    return MessageResponse(detail="Marquée comme lue.")
