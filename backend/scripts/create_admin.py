#!/usr/bin/env python3
# 2026-10-02 — création / gestion du compte Admin (convention vusine-dev).
# Usage :
#   python create_admin.py MATRICULE NOM                    (création, mot de passe demandé)
#   python create_admin.py MATRICULE --reset-password       (reset par l'Admin, pas de self-reset V1)
# Mot de passe : >= 10 caractères, jamais stocké en clair (bcrypt).
import getpass
import sys

sys.path.insert(0, ".")

from sqlalchemy.orm import Session  # noqa: E402

from app.core.database import SessionLocal  # noqa: E402
from app.core.security import hash_password  # noqa: E402
from app.models.rating import Salarie  # noqa: E402
from app.services.audit import log_action  # noqa: E402


def main() -> None:
    args = sys.argv[1:]
    if len(args) < 2:
        print("Usage : create_admin.py MATRICULE NOM [--reset-password]")
        sys.exit(1)

    matricule, nom = args[0], args[1]
    reset = "--reset-password" in args

    db: Session = SessionLocal()
    user = db.query(Salarie).filter(Salarie.matricule == matricule).first()

    if reset:
        if not user:
            print(f"Erreur : le matricule {matricule} n'existe pas.")
            sys.exit(1)
        password = getpass.getpass("Nouveau mot de passe (>= 10 caractères) : ")
    else:
        if user:
            print(f"Erreur : le matricule {matricule} existe déjà. "
                  "Utilisez --reset-password.")
            sys.exit(1)
        password = getpass.getpass("Mot de passe (>= 10 caractères) : ")
        confirm = getpass.getpass("Confirmation : ")
        if password != confirm:
            print("Erreur : les mots de passe ne correspondent pas.")
            sys.exit(1)

    if len(password) < 10:
        print("Erreur : le mot de passe doit faire au moins 10 caractères.")
        sys.exit(1)

    if reset:
        log_action(db, auteur_id=user.id, action="RESET_PASSWORD",
                  table_cible="salaries", enregistrement_id=user.id)
        user.password_hash = hash_password(password)
        user.must_change_password = False
        print(f"Mot de passe réinitialisé pour {matricule}.")
    else:
        user = Salarie(
            matricule=matricule, nom=nom, is_admin=True,
            password_hash=hash_password(password),
        )
        db.add(user)
        print(f"Admin {matricule} créé.")

    db.commit()
    db.close()


if __name__ == "__main__":
    main()
