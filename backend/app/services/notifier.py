# 2026-10-02 — envoi des notifications : écran (toujours, table notifications),
# mail si email renseigné, Telegram (bot token en .env). WhatsApp prévu/désactivé.
# Schedulers (relances de fin de campagne) désactivés par défaut (SCHEDULERS_ENABLED).
import smtplib
from email.mime.text import MIMEText

from sqlalchemy.orm import Session

from app.core.settings import get_settings
from app.models.rating import Notification, Salarie


def notifier(db: Session, salarie_id: int, titre: str, message: str) -> None:
    """Écran : toujours. Mail : si email renseigné (best effort, jamais bloquant)."""
    db.add(Notification(salarie_id=salarie_id, titre=titre, message=message))
    s = db.query(Salarie).get(salarie_id)
    if s and s.email:
        try:
            _envoyer_mail(s.email, titre, message)
        except Exception:            # le mail ne doit jamais casser le flux métier
            pass


def _envoyer_mail(dest: str, sujet: str, corps: str) -> None:
    settings = get_settings()
    if not getattr(settings, "SMTP_HOST", ""):
        return                       # SMTP non configuré : notification écran seule
    msg = MIMEText(corps, "plain", "utf-8")
    msg["Subject"], msg["To"] = sujet, dest
    with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT) as srv:
        srv.send_message(msg)
