#!/usr/bin/env bash
# ============================================================================
# PATCH 10 — EVALPOINT (rating-dev) — 04/10/2026
#   ROADMAP PRO/PREMIUM COMPLÈTE (NAVIGATION / TABLEAUX DE BORD : abandonnés
#   par décision utilisateur — non traités ici).
#     1. EXPORTS Excel (openpyxl) + PDF (document HTML prêt à imprimer)
#        depuis la vue CAMPAGNES (fiches + statuts + décision + signatures).
#     2. SIGNATURE ÉLECTRONIQUE N / N+1 / N+2 : table signatures (empreinte
#        SHA-256 + horodatage), bouton « SIGNER MON ÉTAPE » sur la fiche,
#        badges « SIGNÉ … le … », exports Excel mentionnent les signatures.
#     3. RELANCES AUTOMATIQUES des retardataires : aperçu + envoi (badge
#        cloche) avec anti-spam 24 h, + script cron backend/relances_cron.py.
#     4. CHECK-INS TRIMESTRIELS N/N+1 : table + API + vue CHECK-INS.
#     5. OBJECTIFS OKR : table + KRs avec avancement + vue OBJECTIFS.
#     6. AUTO-ÉVAL ASSISTÉE : barre d'avancement de son étape sur la fiche
#        (chaque réponse est déjà persistée immédiatement côté serveur).
#     7. MODE SOMBRE : bascule dans la topbar, tokens [data-theme=dark].
#     8. ONBOARDING GUIDÉ : composant TourGuide (première connexion).
#     9. BENCHMARK ANONYMISÉ inter-sections (Admin, sections < 5 masquées).
#   PRÉREQUIS : patch9.sh appliqué (n2_id, mon_role corrigé, cutoff 6 mois).
#   Idempotent. Usage : bash patch10.sh  (racine de rating-dev/, venv backend actif)
# ============================================================================
set -euo pipefail

if [ ! -d backend/app ] || [ ! -d frontend/src ]; then
  echo "ERREUR : lancez ce script depuis la racine de rating-dev/."
  exit 1
fi

for f in backend/app/models/rating.py backend/app/main.py \
         frontend/src/router/index.js frontend/src/App.vue \
         frontend/src/views/FicheEvaluationView.vue \
         frontend/src/views/CampagnesView.vue frontend/src/style.css; do
  cp "$f" "$f.bak-patch10"
done

# Écriture idempotente d'un NOUVEAU fichier (stdin) : inchangé si déjà PATCH 10.
ecrire() {
  if [ -f "$1" ] && grep -q "PATCH 10" "$1" 2>/dev/null; then
    cat > /dev/null; echo "  = $1 (déjà présent)"
  else
    cat > "$1"; echo "  + $1"
  fi
}

echo "== PATCH 10 : nouveaux fichiers backend =="

# ---------------------------------------------------------------- signatures
ecrire backend/app/api/signatures.py <<'EOF'
# PATCH 10 — signature électronique N / N+1 / N+2 (empreinte SHA-256 horodatée).
import hashlib
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.rating import Evaluation, Salarie, Signature
from app.services.evaluations import mon_role

router = APIRouter(prefix="/api/evaluations", tags=["Signatures"])


def _signatures(db: Session, evaluation_id: int) -> list[Signature]:
    return (
        db.query(Signature)
        .filter(Signature.evaluation_id == evaluation_id)
        .order_by(Signature.horodatage)
        .all()
    )


@router.get("/{evaluation_id}/signatures")
def lister(evaluation_id: int, db: Session = Depends(get_db),
           user: Salarie = Depends(get_current_user)):
    ev = db.query(Evaluation).get(evaluation_id)
    if not ev:
        raise HTTPException(404, "Fiche introuvable.")
    if mon_role(db, ev, user) is None:
        raise HTTPException(403, "Accès refusé.")
    out = []
    for s in _signatures(db, evaluation_id):
        a = db.query(Salarie).get(s.auteur_id)
        out.append({
            "id": s.id, "etape": s.etape,
            "auteur": a.full_name if a else "?",
            "date": s.horodatage.strftime("%d/%m/%Y %H:%M"),
            "empreinte": s.empreinte,
        })
    return out


@router.post("/{evaluation_id}/signer", status_code=201)
def signer(evaluation_id: int, db: Session = Depends(get_db),
           user: Salarie = Depends(get_current_user)):
    """Appose la signature électronique de l'étape clôturée : l'empreinte
    SHA-256 engage (n° fiche | étape | signataire | horodatage)."""
    ev = db.query(Evaluation).get(evaluation_id)
    if not ev:
        raise HTTPException(404, "Fiche introuvable.")
    role = mon_role(db, ev, user)
    if role in (None, "ADMIN"):
        raise HTTPException(403, "Seuls N, N+1 ou N+2 peuvent signer cette fiche.")
    ok = (
        (role == "N" and ev.statut_n == "Clôturée")
        or (role == "N+1" and ev.statut_n1 == "Clôturée")
        or (role == "N+2" and ev.statut_global == "Approuvé")
    )
    if not ok:
        raise HTTPException(422, f"Votre étape {role} n'est pas encore clôturée : signature impossible.")
    if any(s.etape == role for s in _signatures(db, evaluation_id)):
        raise HTTPException(409, f"Étape {role} déjà signée.")
    emp = hashlib.sha256(
        f"{ev.numero}|{role}|{user.matricule}|{datetime.now().isoformat()}".encode()
    ).hexdigest()
    db.add(Signature(evaluation_id=evaluation_id, etape=role,
                     auteur_id=user.id, empreinte=emp))
    db.commit()
    return {"detail": f"Étape {role} signée électroniquement.", "empreinte": emp}
EOF

# ------------------------------------------------------------------ check-ins
ecrire backend/app/api/checkins.py <<'EOF'
# PATCH 10 — check-ins trimestriels N/N+1 (roadmap PRO) : points forts,
# axes d'amélioration, décision, date de réunion. Périmètre relationnel.
from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.rating import Checkin, Salarie
from app.services.hierarchie import collaborateurs_directs, collaborateurs_indirects

router = APIRouter(prefix="/api/checkins", tags=["Check-ins"])


class CheckinIn(BaseModel):
    salarie_id: int
    trimestre: int
    annee: int
    points_forts: str
    axes_amelioration: str


def _perimetre(db: Session, user: Salarie) -> list[int]:
    ids = [s.id for s in collaborateurs_directs(db, user.id)]
    ids += [s.id for s in collaborateurs_indirects(db, user.id)]
    return ids


def _dict(db: Session, c: Checkin) -> dict:
    s = db.query(Salarie).get(c.salarie_id)
    a = db.query(Salarie).get(c.auteur_id)
    return {
        "id": c.id, "salarie_id": c.salarie_id,
        "matricule": s.matricule if s else "?", "nom": s.full_name if s else "?",
        "trimestre": c.trimestre, "annee": c.annee,
        "points_forts": c.points_forts, "axes_amelioration": c.axes_amelioration,
        "decision": c.decision, "date_reunion": c.date_reunion,
        "auteur": a.full_name if a else "?",
    }


@router.get("/collaborateurs")
def collaborateurs(db: Session = Depends(get_db),
                   user: Salarie = Depends(get_current_user)):
    if user.is_admin:
        cols = db.query(Salarie).filter(
            Salarie.is_active.is_(True), Salarie.is_admin.is_(False)).all()
    else:
        cols = collaborateurs_directs(db, user.id) + collaborateurs_indirects(db, user.id)
    return [{"id": s.id, "matricule": s.matricule, "nom": s.full_name} for s in cols]


@router.get("")
def lister(trimestre: int | None = None, annee: int | None = None,
           db: Session = Depends(get_db), user: Salarie = Depends(get_current_user)):
    q = db.query(Checkin)
    if not user.is_admin:
        per = _perimetre(db, user)
        per.append(user.id)
        q = q.filter(Checkin.salarie_id.in_(per))
    if trimestre:
        q = q.filter(Checkin.trimestre == trimestre)
    if annee:
        q = q.filter(Checkin.annee == annee)
    return [_dict(db, c) for c in q.order_by(Checkin.annee.desc(), Checkin.trimestre.desc()).all()]


@router.post("", status_code=201)
def creer(p: CheckinIn, db: Session = Depends(get_db),
          user: Salarie = Depends(get_current_user)):
    if not (1 <= p.trimestre <= 4) or p.annee < 2000:
        raise HTTPException(422, "Trimestre (1-4) ou année invalide.")
    if not p.points_forts.strip() or not p.axes_amelioration.strip():
        raise HTTPException(422, "Points forts et axes d'amélioration obligatoires.")
    if not user.is_admin:
        per = _perimetre(db, user)
        if p.salarie_id not in per and p.salarie_id != user.id:
            raise HTTPException(403, "Ce salarié n'est pas dans votre périmètre.")
    c = Checkin(salarie_id=p.salarie_id, auteur_id=user.id,
                trimestre=p.trimestre, annee=p.annee,
                points_forts=p.points_forts.strip(),
                axes_amelioration=p.axes_amelioration.strip())
    db.add(c); db.commit(); db.refresh(c)
    return _dict(db, c)


@router.post("/{checkin_id}/cloturer")
def cloturer(checkin_id: int, db: Session = Depends(get_db),
             user: Salarie = Depends(get_current_user)):
    c = db.query(Checkin).get(checkin_id)
    if not c:
        raise HTTPException(404, "Check-in introuvable.")
    if not user.is_admin and c.auteur_id != user.id:
        raise HTTPException(403, "Seul l'auteur (ou l'Admin) peut clôturer.")
    c.decision = "Clôturé"
    c.date_reunion = date.today()
    db.commit()
    return {"detail": "Check-in clôturé."}
EOF

# ------------------------------------------------------------------ objectifs
ecrire backend/app/api/objectifs.py <<'EOF'
# PATCH 10 — objectifs OKR trimestriels : objectif + résultats clés avec
# avancement (0-100 %). Périmètre relationnel N/N+1/N+2/Admin.
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.rating import Objectif, ObjectifKr, Salarie
from app.services.hierarchie import collaborateurs_directs, collaborateurs_indirects

router = APIRouter(prefix="/api/objectifs", tags=["Objectifs OKR"])


class ObjectifIn(BaseModel):
    salarie_id: int
    titre: str
    description: str | None = None
    trimestre: int
    annee: int


class KrIn(BaseModel):
    libelle: str


class AvancementIn(BaseModel):
    avancement: int


def _perimetre(db: Session, user: Salarie) -> list[int]:
    ids = [s.id for s in collaborateurs_directs(db, user.id)]
    ids += [s.id for s in collaborateurs_indirects(db, user.id)]
    return ids


def _dict(db: Session, o: Objectif) -> dict:
    s = db.query(Salarie).get(o.salarie_id)
    return {
        "id": o.id, "salarie_id": o.salarie_id,
        "matricule": s.matricule if s else "?", "nom": s.full_name if s else "?",
        "titre": o.titre, "description": o.description,
        "trimestre": o.trimestre, "annee": o.annee, "statut": o.statut,
        "krs": [{"id": k.id, "libelle": k.libelle, "avancement": k.avancement}
                for k in db.query(ObjectifKr)
                .filter(ObjectifKr.objectif_id == o.id)
                .order_by(ObjectifKr.id).all()],
    }


@router.get("")
def lister(trimestre: int | None = None, annee: int | None = None,
           db: Session = Depends(get_db), user: Salarie = Depends(get_current_user)):
    q = db.query(Objectif)
    if not user.is_admin:
        per = _perimetre(db, user)
        per.append(user.id)
        q = q.filter(Objectif.salarie_id.in_(per))
    if trimestre:
        q = q.filter(Objectif.trimestre == trimestre)
    if annee:
        q = q.filter(Objectif.annee == annee)
    return [_dict(db, o) for o in q.order_by(Objectif.annee.desc(), Objectif.trimestre.desc()).all()]


@router.post("", status_code=201)
def creer(p: ObjectifIn, db: Session = Depends(get_db),
          user: Salarie = Depends(get_current_user)):
    if not p.titre.strip():
        raise HTTPException(422, "Titre obligatoire.")
    if not (1 <= p.trimestre <= 4) or p.annee < 2000:
        raise HTTPException(422, "Trimestre (1-4) ou année invalide.")
    if not user.is_admin:
        per = _perimetre(db, user)
        if p.salarie_id not in per and p.salarie_id != user.id:
            raise HTTPException(403, "Ce salarié n'est pas dans votre périmètre.")
    o = Objectif(salarie_id=p.salarie_id, auteur_id=user.id,
                 titre=p.titre.strip(),
                 description=(p.description or "").strip() or None,
                 trimestre=p.trimestre, annee=p.annee)
    db.add(o); db.commit(); db.refresh(o)
    return _dict(db, o)


@router.post("/{objectif_id}/krs", status_code=201)
def ajouter_kr(objectif_id: int, p: KrIn, db: Session = Depends(get_db),
               user: Salarie = Depends(get_current_user)):
    o = db.query(Objectif).get(objectif_id)
    if not o:
        raise HTTPException(404, "Objectif introuvable.")
    if not user.is_admin and o.auteur_id != user.id:
        raise HTTPException(403, "Seul l'auteur (ou l'Admin) peut ajouter un résultat clé.")
    if not p.libelle.strip():
        raise HTTPException(422, "Libellé obligatoire.")
    db.add(ObjectifKr(objectif_id=o.id, libelle=p.libelle.strip()))
    db.commit()
    return _dict(db, o)


@router.post("/krs/{kr_id}/avancement")
def avancer(kr_id: int, p: AvancementIn, db: Session = Depends(get_db),
            user: Salarie = Depends(get_current_user)):
    k = db.query(ObjectifKr).get(kr_id)
    if not k:
        raise HTTPException(404, "Résultat clé introuvable.")
    o = db.query(Objectif).get(k.objectif_id)
    if not user.is_admin and o.auteur_id != user.id and o.salarie_id != user.id:
        raise HTTPException(403, "Non autorisé.")
    if not (0 <= p.avancement <= 100):
        raise HTTPException(422, "Avancement entre 0 et 100.")
    k.avancement = p.avancement
    db.commit()
    return {"detail": "Avancement mis à jour."}


@router.post("/{objectif_id}/cloturer")
def cloturer(objectif_id: int, db: Session = Depends(get_db),
             user: Salarie = Depends(get_current_user)):
    o = db.query(Objectif).get(objectif_id)
    if not o:
        raise HTTPException(404, "Objectif introuvable.")
    if not user.is_admin and o.auteur_id != user.id:
        raise HTTPException(403, "Seul l'auteur (ou l'Admin) peut clôturer.")
    o.statut = "Clôturé"
    db.commit()
    return {"detail": "Objectif clôturé."}
EOF

# ------------------------------------------------------------------- relances
ecrire backend/app/services/relances.py <<'EOF'
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
EOF

ecrire backend/app/api/relances.py <<'EOF'
# PATCH 10 — API relances : aperçu des retardataires + envoi (Admin).
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import require_admin
from app.models.rating import Campagne, Salarie
from app.services.relances import envoyer_relances, retardataires

router = APIRouter(prefix="/api/relances", tags=["Relances"])


@router.get("/campagne/{campagne_id}/apercu")
def apercu(campagne_id: int, db: Session = Depends(get_db),
           admin: Salarie = Depends(require_admin)):
    c = db.query(Campagne).get(campagne_id)
    if not c:
        raise HTTPException(404, "Campagne introuvable.")
    ret = retardataires(db, c)
    out = {}
    for etape, fiches in ret.items():
        out[etape] = [{"numero": e.numero, "matricule": s.matricule,
                       "nom": s.full_name} for e, s, _ in fiches]
    return out


@router.post("/campagne/{campagne_id}/envoyer")
def envoyer(campagne_id: int, db: Session = Depends(get_db),
            admin: Salarie = Depends(require_admin)):
    c = db.query(Campagne).get(campagne_id)
    if not c:
        raise HTTPException(404, "Campagne introuvable.")
    if c.statut != "Ouverte":
        raise HTTPException(422, "Les relances ne concernent que les campagnes Ouvertes.")
    return envoyer_relances(db, c)
EOF

ecrire backend/relances_cron.py <<'EOF'
# PATCH 10 — relances automatiques quotidiennes (cron). Exemple crontab :
#   0 8 * * * cd /opt/rating-dev/backend && ./venv/bin/python relances_cron.py >> relances.log 2>&1
from app.core.database import SessionLocal
from app.models.rating import Campagne
from app.services.relances import envoyer_relances

total = 0
with SessionLocal() as db:
    for c in db.query(Campagne).filter(Campagne.statut == "Ouverte").all():
        r = envoyer_relances(db, c)
        total += r["notifiees"]
        print(f"{c.nom} : {r['notifiees']} notification(s) envoyée(s), "
              f"{r['deja_relancees']} ignorée(s) (anti-spam 24 h) — "
              f"N:{r['n']} N+1:{r['n1']} N+2:{r['n2']}")
print("Relances terminées :", total)
EOF

# -------------------------------------------------------------------- exports
ecrire backend/app/api/exports.py <<'EOF'
# PATCH 10 — exports Excel (openpyxl, déjà utilisé par l'import) et PDF
# (document HTML prêt à imprimer : ouvrir puis Ctrl+P -> Enregistrer en PDF).
import io

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response, StreamingResponse
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import require_admin
from app.models.rating import (
    Approbation, Campagne, CritereDetail, Emploi, Evaluation,
    EvaluationLigne, Salarie, Section, Signature,
)

router = APIRouter(prefix="/api/exports", tags=["Exports"])

ENTETES = ["N° FICHE", "Matricule", "Nom", "Section", "Emploi", "Statut N",
           "Statut N+1", "Statut N+2", "Global", "Décision N+2",
           "Commentaire global", "Signé N le", "Signé N+1 le", "Signé N+2 le"]


def _lignes_campagne(db: Session, campagne_id: int):
    evals = (
        db.query(Evaluation)
        .filter(Evaluation.campagne_id == campagne_id)
        .order_by(Evaluation.numero)
        .all()
    )
    rows = []
    for e in evals:
        s = db.query(Salarie).get(e.salarie_id)
        sect = db.query(Section).get(s.section_id) if s and s.section_id else None
        emp = db.query(Emploi).get(s.emploi_id) if s and s.emploi_id else None
        app = db.query(Approbation).filter(Approbation.evaluation_id == e.id).first()
        sigs = {x.etape: x.horodatage.strftime("%d/%m/%Y %H:%M")
                for x in db.query(Signature)
                .filter(Signature.evaluation_id == e.id).all()}
        rows.append([
            e.numero, s.matricule if s else "?", s.full_name if s else "?",
            sect.libelle if sect else "",
            emp.libelle if emp else "",
            e.statut_n, e.statut_n1, e.statut_n2, e.statut_global,
            app.decision if app else "",
            (e.commentaire_global or "")[:200],
            sigs.get("N", ""), sigs.get("N+1", ""), sigs.get("N+2", ""),
        ])
    return rows


@router.get("/campagne/{campagne_id}/excel")
def campagne_excel(campagne_id: int, db: Session = Depends(get_db),
                   admin: Salarie = Depends(require_admin)):
    from openpyxl import Workbook
    from openpyxl.styles import Font, PatternFill

    c = db.query(Campagne).get(campagne_id)
    if not c:
        raise HTTPException(404, "Campagne introuvable.")
    wb = Workbook()
    ws = wb.active
    ws.title = "Fiches"
    ws.append([f"CAMPAGNE : {c.nom} — exercice {c.exercice} — {c.statut}"])
    ws.append([])
    ws.append(ENTETES)
    for cell in ws[3]:
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = PatternFill("solid", fgColor="1B4D7A")
    for row in _lignes_campagne(db, campagne_id):
        ws.append(row)
    for col in range(1, len(ENTETES) + 1):
        ws.column_dimensions[ws.cell(row=3, column=col).column_letter].width = 18
    buf = io.BytesIO()
    wb.save(buf)
    buf.seek(0)
    return StreamingResponse(
        buf,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="campagne_{campagne_id}.xlsx"'},
    )


@router.get("/campagne/{campagne_id}/pdf")
def campagne_pdf(campagne_id: int, db: Session = Depends(get_db),
                 admin: Salarie = Depends(require_admin)):
    """Document HTML print-ready (aucune dépendance PDF) : Ctrl+P -> PDF."""
    c = db.query(Campagne).get(campagne_id)
    if not c:
        raise HTTPException(404, "Campagne introuvable.")
    tr = "".join(
        "<tr>" + "".join(f"<td>{v}</td>" for v in row) + "</tr>"
        for row in _lignes_campagne(db, campagne_id)
    )
    th = "".join(f"<th>{h}</th>" for h in ENTETES)
    html = f"""<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8">
<title>Campagne {c.nom} — EVALPOINT</title><style>
body {{ font-family: Inter, Arial, sans-serif; font-size: 10px; margin: 18px; }}
h1 {{ font-size: 16px; color: #1B4D7A; }}
table {{ border-collapse: collapse; width: 100%; }}
th, td {{ border: 1px solid #cbd5e1; padding: 4px 6px; text-align: left; }}
th {{ background: #1B4D7A; color: #fff; }}
@media print {{ body {{ margin: 6px; }} }}
</style></head><body>
<h1>EVALPOINT — Campagne « {c.nom} » — exercice {c.exercice} — {c.statut}</h1>
<p>Document généré le {c.created_at.strftime('%d/%m/%Y')}. Pour obtenir le PDF :
Ctrl+P (ou Cmd+P) puis « Enregistrer au format PDF ».</p>
<table><thead><tr>{th}</tr></thead><tbody>{tr}</tbody></table>
</body></html>"""
    return Response(html, media_type="text/html; charset=utf-8")


@router.get("/evaluation/{evaluation_id}/excel")
def fiche_excel(evaluation_id: int, db: Session = Depends(get_db),
                admin: Salarie = Depends(require_admin)):
    """Export Excel d'UNE fiche : toutes les lignes QCM N et N+1."""
    from openpyxl import Workbook

    e = db.query(Evaluation).get(evaluation_id)
    if not e:
        raise HTTPException(404, "Fiche introuvable.")
    s = db.query(Salarie).get(e.salarie_id)
    lignes = (
        db.query(EvaluationLigne)
        .filter(EvaluationLigne.evaluation_id == e.id)
        .order_by(EvaluationLigne.profil_id, EvaluationLigne.critere_id,
                  EvaluationLigne.etape)
        .all()
    )
    wb = Workbook()
    ws = wb.active
    ws.title = "Fiche " + e.numero
    ws.append([f"FICHE {e.numero} — {s.full_name if s else ''}"])
    ws.append(["Profil", "Critère", "Étape", "Description cochée", "Commentaire"])
    for l in lignes:
        d = db.query(CritereDetail).get(l.critere_detail_id) if l.critere_detail_id else None
        ws.append([l.profil_id, l.critere_id, l.etape,
                   d.libelle_descriptif if d else "", l.commentaire or ""])
    buf = io.BytesIO()
    wb.save(buf)
    buf.seek(0)
    return StreamingResponse(
        buf,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="fiche_{e.numero}.xlsx"'},
    )
EOF

# ------------------------------------------------------------------ benchmark
ecrire backend/app/api/bench.py <<'EOF'
# PATCH 10 — benchmark anonymisé inter-sections (Admin) : agrégats par section,
# sections de moins de 5 fiches masquées (« Section anonymisée »).
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import require_admin
from app.models.rating import Evaluation, Salarie, Section

router = APIRouter(prefix="/api/bench", tags=["Benchmark"])


@router.get("/sections")
def sections(db: Session = Depends(get_db),
             admin: Salarie = Depends(require_admin)):
    agg: dict = {}
    evals = db.query(Evaluation).all()
    for e in evals:
        s = db.query(Salarie).get(e.salarie_id)
        if not s or not s.section_id:
            continue
        sect = db.query(Section).get(s.section_id)
        lib = sect.libelle if sect else "?"
        a = agg.setdefault(lib, {"nb": 0, "n": 0, "n1": 0, "app": 0})
        a["nb"] += 1
        if e.statut_n == "Clôturée":
            a["n"] += 1
        if e.statut_n1 == "Clôturée":
            a["n1"] += 1
        if e.statut_global == "Approuvé":
            a["app"] += 1
    out = []
    for lib, a in sorted(agg.items(), key=lambda kv: -kv[1]["nb"]):
        anonyme = a["nb"] < 5
        out.append({
            "section": "Section anonymisée (< 5 fiches)" if anonyme else lib,
            "anonyme": anonyme, "nb_fiches": a["nb"],
            "pct_n": round(100 * a["n"] / a["nb"]),
            "pct_n1": round(100 * a["n1"] / a["nb"]),
            "pct_approuvees": round(100 * a["app"] / a["nb"]),
        })
    return out
EOF

echo "== PATCH 10 : nouveaux fichiers frontend =="

# ------------------------------------------------------------------- TourGuide
ecrire frontend/src/components/TourGuide.vue <<'EOF'
<!-- PATCH 10 — onboarding guidé : visite en 6 étapes à la 1re connexion,
     relançable depuis MON ESPACE (localStorage 'tourFait'). -->
<script setup>
import { ref } from 'vue'
import { X, ChevronLeft, ChevronRight } from 'lucide-vue-next'

const ETAPES = [
  { titre: 'Bienvenue sur EVALPOINT', texte: "La plateforme d'évaluation du personnel SIVOP. Cette visite rapide vous présente les écrans essentiels (30 secondes)." },
  { titre: 'MON ESPACE', texte: 'Votre page d\'accueil : rôle (N, N+1, N+2), fiches à traiter, notifications et raccourcis.' },
  { titre: 'EVALUATIONS', texte: 'La campagne active et la liste des fiches de votre périmètre : filtrer par section, ouvrir une fiche.' },
  { titre: 'Votre fiche (QCM)', texte: "Cliquez une cellule de votre étape : cochez la description qui vous décrit le mieux, ajoutez un commentaire (obligatoire). Chaque réponse est enregistrée immédiatement — une barre d'avancement vous suit." },
  { titre: 'Cadenas & signatures', texte: "Clôturez votre étape (cadenas, irréversible), puis signez électroniquement : badge SIGNÉ horodaté avec empreinte SHA-256." },
  { titre: 'Check-ins & objectifs', texte: 'Entre les campagnes : check-ins trimestriels et objectifs OKR avec vos collaborateurs (menus CHECK-INS / OBJECTIFS).' },
]
const visible = ref(!localStorage.getItem('tourFait') && !!localStorage.getItem('token'))
const etape = ref(0)

function suivant() { etape.value < ETAPES.length - 1 ? etape.value++ : terminer() }
function precedent() { if (etape.value > 0) etape.value-- }
function terminer() { localStorage.setItem('tourFait', '1'); visible.value = false }
</script>

<template>
  <div v-if="visible" class="tour-overlay">
    <div class="tour-box">
      <button class="tour-x" title="Fermer la visite" @click="terminer"><X :size="18" /></button>
      <div class="tour-num">{{ etape + 1 }} / {{ ETAPES.length }}</div>
      <h4>{{ ETAPES[etape].titre }}</h4>
      <p>{{ ETAPES[etape].texte }}</p>
      <div class="tour-actions">
        <button v-if="etape > 0" class="vbtn ghost" @click="precedent"><ChevronLeft :size="14" /> PRÉCÉDENT</button>
        <span style="flex:1"></span>
        <button class="vbtn ghost" @click="terminer">PASSER</button>
        <button class="vbtn" @click="suivant">
          {{ etape === ETAPES.length - 1 ? 'TERMINER' : 'SUIVANT' }} <ChevronRight :size="14" />
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.tour-overlay { position: fixed; inset: 0; background: rgba(15, 23, 42, .55); z-index: 1200; display: flex; align-items: center; justify-content: center; padding: 16px; }
.tour-box { position: relative; background: var(--color-surface); border-radius: var(--radius-lg); box-shadow: var(--shadow-card); max-width: 480px; width: 100%; padding: 22px; }
.tour-x { position: absolute; top: 10px; right: 10px; background: none; border: none; cursor: pointer; color: var(--color-text-muted); }
.tour-num { font-size: 11px; font-weight: 700; color: var(--color-brand); }
h4 { margin: 4px 0 8px; font-size: 15px; color: var(--color-brand-dark); }
p { font-size: 13px; color: var(--color-text); line-height: 1.5; }
.tour-actions { display: flex; gap: 8px; margin-top: 16px; align-items: center; }
</style>
EOF

# ------------------------------------------------------------------ CheckinsView
ecrire frontend/src/views/CheckinsView.vue <<'EOF'
<!-- PATCH 10 — check-ins trimestriels N/N+1 : liste du périmètre, création,
     clôture. Mobile : cartes (adaptation patch 8). -->
<script setup>
import { onMounted, ref } from 'vue'
import { Plus, Check, Lock } from 'lucide-vue-next'
import api from '../api/client'
import { useConfirm } from '../composables/useConfirm'

const { confirm } = useConfirm()
const liste = ref([])
const collaborateurs = ref([])
const erreur = ref('')
const message = ref('')
const estMobile = window.matchMedia('(max-width: 768px)').matches
const annee = ref(new Date().getFullYear())
const trimestre = ref(Math.min(4, Math.floor(new Date().getMonth() / 3) + 1))
const modale = ref(false)
const forme = ref({ salarie_id: null, points_forts: '', axes_amelioration: '' })

async function charger() {
  erreur.value = ''
  try {
    const [l, c] = await Promise.all([
      api.get('/checkins', { params: { trimestre: trimestre.value, annee: annee.value } }),
      api.get('/checkins/collaborateurs'),
    ])
    liste.value = l.data
    collaborateurs.value = c.data
  } catch (e) { erreur.value = e.response?.data?.detail || 'Chargement impossible.' }
}
onMounted(charger)

function ouvrir() { forme.value = { salarie_id: null, points_forts: '', axes_amelioration: '' }; modale.value = true }

async function enregistrer() {
  if (!forme.value.salarie_id) { erreur.value = 'Choisissez un collaborateur.'; return }
  if (!forme.value.points_forts.trim() || !forme.value.axes_amelioration.trim()) {
    erreur.value = 'Points forts et axes d\'amélioration obligatoires.'; return
  }
  try {
    await api.post('/checkins', { ...forme.value, trimestre: trimestre.value, annee: annee.value })
    modale.value = false; message.value = 'Check-in enregistré.'; await charger()
  } catch (e) { erreur.value = e.response?.data?.detail }
}

async function cloturer(c) {
  const ok = await confirm({
    title: 'Clôturer le check-in',
    message: `Clôturer le check-in de ${c.nom} (T${c.trimestre} ${c.annee}) ? La date du jour sera retenue comme date de réunion.`,
    confirmLabel: 'Clôturer',
  })
  if (!ok) return
  try {
    await api.post('/checkins/' + c.id + '/cloturer')
    message.value = 'Check-in clôturé.'; await charger()
  } catch (e) { erreur.value = e.response?.data?.detail }
}
</script>

<template>
  <div>
    <h3>CHECK-INS TRIMESTRIELS</h3>
    <div class="forme">
      <div class="field"><label>TRIMESTRE</label>
        <select v-model="trimestre" @change="charger">
          <option :value="1">T1</option><option :value="2">T2</option>
          <option :value="3">T3</option><option :value="4">T4</option>
        </select></div>
      <div class="field"><label>ANNÉE</label><input type="number" v-model="annee" @change="charger" /></div>
      <button class="btn" title="Planifier un nouveau check-in trimestriel" @click="ouvrir">
        <Plus :size="14" /> NOUVEAU CHECK-IN</button>
    </div>
    <div v-if="message" class="ok">{{ message }}</div>
    <div v-if="erreur" class="error">{{ erreur }}</div>

    <table v-if="!estMobile" class="data">
      <thead><tr><th>COLLABORATEUR</th><th>TRIMESTRE</th><th>POINTS FORTS</th><th>AXES D'AMÉLIORATION</th><th>DÉCISION</th><th>ACTIONS</th></tr></thead>
      <tbody>
        <tr v-for="c in liste" :key="c.id">
          <td>{{ c.matricule }} — {{ c.nom }}</td>
          <td>T{{ c.trimestre }} {{ c.annee }}</td>
          <td>{{ c.points_forts }}</td>
          <td>{{ c.axes_amelioration }}</td>
          <td><span class="badge-statut" :class="c.decision === 'Clôturé' ? 'statut-vert' : 'statut-orange'">{{ c.decision }}</span></td>
          <td><button v-if="c.decision !== 'Clôturé'" class="icon-btn" style="color: var(--color-vert)"
            title="Clôturer ce check-in (date du jour)" @click="cloturer(c)"><Lock :size="15" /></button></td>
        </tr>
      </tbody>
    </table>

    <div v-else>
      <div v-for="c in liste" :key="c.id" class="card" style="margin-bottom:10px;">
        <div><b>{{ c.matricule }} — {{ c.nom }}</b> · T{{ c.trimestre }} {{ c.annee }}</div>
        <div style="font-size:12px; margin-top:6px;"><b>Points forts :</b> {{ c.points_forts }}</div>
        <div style="font-size:12px; margin-top:4px;"><b>Axes :</b> {{ c.axes_amelioration }}</div>
        <div style="margin-top:8px; display:flex; gap:8px; align-items:center;">
          <span class="badge-statut" :class="c.decision === 'Clôturé' ? 'statut-vert' : 'statut-orange'">{{ c.decision }}</span>
          <button v-if="c.decision !== 'Clôturé'" class="icon-btn" style="color: var(--color-vert)"
            title="Clôturer ce check-in" @click="cloturer(c)"><Lock :size="15" /></button>
        </div>
      </div>
      <div v-if="!liste.length" style="color: var(--color-text-muted); font-size: 12px;">Aucun check-in ce trimestre.</div>
    </div>

    <div v-if="modale" class="overlay" @click.self="modale = false"></div>
    <div v-if="modale" class="modale">
      <h4>NOUVEAU CHECK-IN — T{{ trimestre }} {{ annee }}</h4>
      <div class="field"><label>COLLABORATEUR</label>
        <select v-model="forme.salarie_id">
          <option :value="null">—</option>
          <option v-for="c in collaborateurs" :key="c.id" :value="c.id">{{ c.matricule }} — {{ c.nom }}</option>
        </select></div>
      <div class="field"><label>POINTS FORTS</label>
        <textarea v-model="forme.points_forts" rows="3" placeholder="Ce qui a bien fonctionné ce trimestre…"></textarea></div>
      <div class="field"><label>AXES D'AMÉLIORATION</label>
        <textarea v-model="forme.axes_amelioration" rows="3" placeholder="Points de progrès, actions convenues…"></textarea></div>
      <div style="display:flex; gap:8px; margin-top:14px; justify-content:flex-end">
        <button class="btn ghost" @click="modale = false">ANNULER</button>
        <button class="btn" @click="enregistrer">ENREGISTRER</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
h3 { font-size: 13px; color: var(--color-brand-dark); margin-bottom: 8px; }
.forme { display: flex; gap: 10px; background: var(--color-surface); padding: 14px; border-radius: var(--radius-md); margin-bottom: 12px; flex-wrap: wrap; }
.field { min-width: 200px; }
.overlay { position: fixed; inset: 0; background: rgba(15, 23, 42, .45); z-index: 900; }
.modale { position: fixed; z-index: 901; top: 50%; left: 50%; transform: translate(-50%, -50%); background: var(--color-surface); border-radius: var(--radius-lg); box-shadow: var(--shadow-card); padding: 20px; width: min(560px, 94vw); }
textarea { width: 100%; }
</style>
EOF

# ------------------------------------------------------------------ ObjectifsView
ecrire frontend/src/views/ObjectifsView.vue <<'EOF'
<!-- PATCH 10 — objectifs OKR : objectifs trimestriels + résultats clés avec
     barre d'avancement, création et clôture. Mobile : cartes. -->
<script setup>
import { onMounted, ref } from 'vue'
import { Plus, Lock, Minus, PlusCircle } from 'lucide-vue-next'
import api from '../api/client'
import { useConfirm } from '../composables/useConfirm'

const { confirm } = useConfirm()
const liste = ref([])
const collaborateurs = ref([])
const erreur = ref('')
const message = ref('')
const estMobile = window.matchMedia('(max-width: 768px)').matches
const annee = ref(new Date().getFullYear())
const trimestre = ref(Math.min(4, Math.floor(new Date().getMonth() / 3) + 1))
const modale = ref(false)
const forme = ref({ salarie_id: null, titre: '', description: '' })
const krNouveau = ref({})   // { [objectifId]: libellé }

async function charger() {
  erreur.value = ''
  try {
    const [l, c] = await Promise.all([
      api.get('/objectifs', { params: { trimestre: trimestre.value, annee: annee.value } }),
      api.get('/checkins/collaborateurs'),
    ])
    liste.value = l.data
    collaborateurs.value = c.data
  } catch (e) { erreur.value = e.response?.data?.detail || 'Chargement impossible.' }
}
onMounted(charger)

function ouvrir() { forme.value = { salarie_id: null, titre: '', description: '' }; modale.value = true }

async function enregistrer() {
  if (!forme.value.salarie_id || !forme.value.titre.trim()) { erreur.value = 'Collaborateur et titre obligatoires.'; return }
  try {
    await api.post('/objectifs', { ...forme.value, trimestre: trimestre.value, annee: annee.value })
    modale.value = false; message.value = 'Objectif créé.'; await charger()
  } catch (e) { erreur.value = e.response?.data?.detail }
}

async function ajouterKr(o) {
  const lib = (krNouveau.value[o.id] || '').trim()
  if (!lib) { erreur.value = 'Libellé du résultat clé obligatoire.'; return }
  try { await api.post('/objectifs/' + o.id + '/krs', { libelle: lib }); krNouveau.value[o.id] = ''; await charger() }
  catch (e) { erreur.value = e.response?.data?.detail }
}

async function avancerKr(o, k, delta) {
  const v = Math.max(0, Math.min(100, (k.avancement || 0) + delta))
  try { await api.post('/objectifs/krs/' + k.id + '/avancement', { avancement: v }); await charger() }
  catch (e) { erreur.value = e.response?.data?.detail }
}

async function cloturer(o) {
  const ok = await confirm({
    title: 'Clôturer l\'objectif',
    message: `Clôturer « ${o.titre} » (${o.nom}) ?`,
    confirmLabel: 'Clôturer',
  })
  if (!ok) return
  try { await api.post('/objectifs/' + o.id + '/cloturer'); message.value = 'Objectif clôturé.'; await charger() }
  catch (e) { erreur.value = e.response?.data?.detail }
}

function barre(v) { return { height: '100%', width: (v || 0) + '%', background: 'var(--color-vert)', transition: 'width .3s' } }
</script>

<template>
  <div>
    <h3>OBJECTIFS OKR</h3>
    <div class="forme">
      <div class="field"><label>TRIMESTRE</label>
        <select v-model="trimestre" @change="charger">
          <option :value="1">T1</option><option :value="2">T2</option>
          <option :value="3">T3</option><option :value="4">T4</option>
        </select></div>
      <div class="field"><label>ANNÉE</label><input type="number" v-model="annee" @change="charger" /></div>
      <button class="btn" title="Fixer un nouvel objectif trimestriel" @click="ouvrir"><Plus :size="14" /> NOUVEL OBJECTIF</button>
    </div>
    <div v-if="message" class="ok">{{ message }}</div>
    <div v-if="erreur" class="error">{{ erreur }}</div>

    <div v-for="o in liste" :key="o.id" class="card obj">
      <div class="obj-titre">
        <b>{{ o.titre }}</b>
        <span class="muted">{{ o.matricule }} — {{ o.nom }} · T{{ o.trimestre }} {{ o.annee }}</span>
        <span class="badge-statut" :class="o.statut === 'Clôturé' ? 'statut-vert' : 'statut-orange'">{{ o.statut }}</span>
        <button v-if="o.statut !== 'Clôturé'" class="icon-btn" style="margin-left:auto; color: var(--color-vert)"
          title="Clôturer cet objectif" @click="cloturer(o)"><Lock :size="15" /></button>
      </div>
      <div v-if="o.description" class="muted" style="margin: 4px 0 8px;">{{ o.description }}</div>
      <div v-for="k in o.krs" :key="k.id" class="kr">
        <span class="kr-lib">{{ k.libelle }}</span>
        <div class="kr-barre"><div :style="barre(k.avancement)"></div></div>
        <span class="kr-pct">{{ k.avancement }} %</span>
        <template v-if="o.statut !== 'Clôturé'">
          <button class="icon-btn" title="Reculer de 10 %" @click="avancerKr(o, k, -10)"><Minus :size="14" /></button>
          <button class="icon-btn" title="Avancer de 10 %" @click="avancerKr(o, k, 10)"><PlusCircle :size="14" /></button>
        </template>
      </div>
      <div v-if="o.statut !== 'Clôturé'" class="kr-ajout">
        <input v-model="krNouveau[o.id]" placeholder="Nouveau résultat clé…" />
        <button class="btn ghost" title="Ajouter ce résultat clé" @click="ajouterKr(o)">AJOUTER</button>
      </div>
      <div v-if="!o.krs.length && o.statut === 'Clôturé'" class="muted">Aucun résultat clé.</div>
    </div>
    <div v-if="!liste.length" class="muted">Aucun objectif ce trimestre.</div>

    <div v-if="modale" class="overlay" @click.self="modale = false"></div>
    <div v-if="modale" class="modale">
      <h4>NOUVEL OBJECTIF — T{{ trimestre }} {{ annee }}</h4>
      <div class="field"><label>COLLABORATEUR</label>
        <select v-model="forme.salarie_id">
          <option :value="null">—</option>
          <option v-for="c in collaborateurs" :key="c.id" :value="c.id">{{ c.matricule }} — {{ c.nom }}</option>
        </select></div>
      <div class="field"><label>TITRE</label><input v-model="forme.titre" placeholder="Ex. Réduire les délais de livraison" /></div>
      <div class="field"><label>DESCRIPTION</label><textarea v-model="forme.description" rows="3" placeholder="Contexte, attendus…"></textarea></div>
      <div style="display:flex; gap:8px; margin-top:14px; justify-content:flex-end">
        <button class="btn ghost" @click="modale = false">ANNULER</button>
        <button class="btn" @click="enregistrer">ENREGISTRER</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
h3 { font-size: 13px; color: var(--color-brand-dark); margin-bottom: 8px; }
.forme { display: flex; gap: 10px; background: var(--color-surface); padding: 14px; border-radius: var(--radius-md); margin-bottom: 12px; flex-wrap: wrap; }
.field { min-width: 200px; }
.card.obj { background: var(--color-surface); border-radius: var(--radius-md); padding: 14px; margin-bottom: 10px; box-shadow: var(--shadow-card); }
.obj-titre { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
.muted { color: var(--color-text-muted); font-size: 12px; }
.kr { display: flex; gap: 8px; align-items: center; margin-top: 8px; flex-wrap: wrap; }
.kr-lib { min-width: 180px; font-size: 13px; }
.kr-barre { flex: 1; min-width: 120px; height: 8px; background: var(--color-border); border-radius: 4px; overflow: hidden; }
.kr-pct { font-size: 12px; font-weight: 700; min-width: 44px; text-align: right; }
.kr-ajout { display: flex; gap: 8px; margin-top: 10px; }
.kr-ajout input { flex: 1; }
.overlay { position: fixed; inset: 0; background: rgba(15, 23, 42, .45); z-index: 900; }
.modale { position: fixed; z-index: 901; top: 50%; left: 50%; transform: translate(-50%, -50%); background: var(--color-surface); border-radius: var(--radius-lg); box-shadow: var(--shadow-card); padding: 20px; width: min(560px, 94vw); }
</style>
EOF

# ---------------------------------------------------------------- BenchmarkView
ecrire frontend/src/views/BenchmarkView.vue <<'EOF'
<!-- PATCH 10 — benchmark anonymisé inter-sections (Admin) : avancement par
     section, sections < 5 fiches masquées pour l'anonymat. -->
<script setup>
import { onMounted, ref } from 'vue'
import api from '../api/client'

const sections = ref([])
const erreur = ref('')

async function charger() {
  try { sections.value = (await api.get('/bench/sections')).data }
  catch (e) { erreur.value = e.response?.data?.detail || 'Chargement impossible.' }
}
onMounted(charger)

function barre(v) { return { height: '100%', width: (v || 0) + '%', transition: 'width .3s' } }
</script>

<template>
  <div>
    <h3>BENCHMARK INTER-SECTIONS (ANONYMISÉ)</h3>
    <p class="muted">Agrégats sur toutes les fiches évaluées. Les sections de moins de 5 fiches
      sont regroupées sous « Section anonymisée » pour préserver la confidentialité.</p>
    <div v-if="erreur" class="error">{{ erreur }}</div>
    <table class="data">
      <thead><tr>
        <th>SECTION</th><th>FICHES</th><th>AUTO-ÉVAL. CLÔTURÉES</th>
        <th>ÉVAL. N+1 CLÔTURÉES</th><th>APPROUVÉES</th>
      </tr></thead>
      <tbody>
        <tr v-for="s in sections" :key="s.section" :class="{ anonyme: s.anonyme }">
          <td>{{ s.section }}</td>
          <td>{{ s.nb_fiches }}</td>
          <td><div class="barre-g"><div :style="barre(s.pct_n)" style="background: var(--color-brand)"></div></div>{{ s.pct_n }} %</td>
          <td><div class="barre-g"><div :style="barre(s.pct_n1)" style="background: var(--color-orange)"></div></div>{{ s.pct_n1 }} %</td>
          <td><div class="barre-g"><div :style="barre(s.pct_approuvees)" style="background: var(--color-vert)"></div></div>{{ s.pct_approuvees }} %</td>
        </tr>
      </tbody>
    </table>
    <div v-if="!sections.length" class="muted">Aucune donnée à comparer pour l'instant.</div>
  </div>
</template>

<style scoped>
h3 { font-size: 13px; color: var(--color-brand-dark); margin-bottom: 8px; }
.muted { color: var(--color-text-muted); font-size: 12px; }
.barre-g { display: inline-block; vertical-align: middle; width: 120px; height: 8px; background: var(--color-border); border-radius: 4px; overflow: hidden; margin-right: 8px; }
tr.anonyme td { color: var(--color-text-muted); font-style: italic; }
</style>
EOF

echo "== PATCH 10 : modifications ciblées (idempotentes) =="

python3 - <<'PYEOF'
# -*- coding: utf-8 -*-
import re, sys, pathlib

def edit(path, repls):
    p = pathlib.Path(path)
    src = p.read_text(encoding="utf-8")
    for pat, rep in repls:
        if re.search(pat, src) is None:
            if rep and rep in src:
                continue   # déjà appliqué
            print(f"ERREUR : motif introuvable dans {path} :\n  {pat[:110]}")
            sys.exit(1)
        src = re.sub(pat, rep, src, count=1, flags=re.S)
    p.write_text(src, encoding="utf-8")
    print("  -", path)

# ---------------------------------------------- modèles ORM (ajout en fin)
edit("backend/app/models/rating.py", [
    (r'class Param\(Base\):\n    __tablename__ = "params"\n    cle: Mapped\[str\] = mapped_column\(VARCHAR\(60\), primary_key=True\)\n    valeur: Mapped\[str\] = mapped_column\(VARCHAR\(300\)\)\n    description: Mapped\[str \| None\] = mapped_column\(Text, nullable=True\)',
     'class Param(Base):\n'
     '    __tablename__ = "params"\n'
     '    cle: Mapped[str] = mapped_column(VARCHAR(60), primary_key=True)\n'
     '    valeur: Mapped[str] = mapped_column(VARCHAR(300))\n'
     '    description: Mapped[str | None] = mapped_column(Text, nullable=True)\n'
     '\n'
     '# ================== PATCH 10 : roadmap PRO/PREMIUM ==================\n'
     '\n'
     'class Signature(Base):\n'
     '    """PATCH 10 — signature électronique N/N+1/N+2 (empreinte SHA-256)."""\n'
     '    __tablename__ = "signatures"\n'
     '    id: Mapped[int] = mapped_column(primary_key=True)\n'
     '    evaluation_id: Mapped[int] = mapped_column(ForeignKey("evaluations.id"))\n'
     '    etape: Mapped[str] = mapped_column(VARCHAR(4))          # N / N+1 / N+2\n'
     '    auteur_id: Mapped[int] = mapped_column(ForeignKey("salaries.id"))\n'
     '    empreinte: Mapped[str] = mapped_column(VARCHAR(64))\n'
     '    horodatage: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.now)\n'
     '    __table_args__ = (UniqueConstraint("evaluation_id", "etape"),)\n'
     '\n'
     'class Checkin(Base):\n'
     '    """PATCH 10 — check-in trimestriel N/N+1 (points forts / axes)."""\n'
     '    __tablename__ = "checkins"\n'
     '    id: Mapped[int] = mapped_column(primary_key=True)\n'
     '    salarie_id: Mapped[int] = mapped_column(ForeignKey("salaries.id"))\n'
     '    auteur_id: Mapped[int] = mapped_column(ForeignKey("salaries.id"))\n'
     '    trimestre: Mapped[int] = mapped_column(SmallInteger)      # 1..4\n'
     '    annee: Mapped[int] = mapped_column(Integer)\n'
     '    points_forts: Mapped[str] = mapped_column(Text)\n'
     '    axes_amelioration: Mapped[str] = mapped_column(Text)\n'
     '    decision: Mapped[str] = mapped_column(VARCHAR(20), default="En cours")\n'
     '    date_reunion: Mapped[date | None] = mapped_column(Date, nullable=True)\n'
     '    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.now)\n'
     '\n'
     'class Objectif(Base):\n'
     '    """PATCH 10 — objectif OKR trimestriel."""\n'
     '    __tablename__ = "objectifs"\n'
     '    id: Mapped[int] = mapped_column(primary_key=True)\n'
     '    salarie_id: Mapped[int] = mapped_column(ForeignKey("salaries.id"))\n'
     '    auteur_id: Mapped[int] = mapped_column(ForeignKey("salaries.id"))\n'
     '    titre: Mapped[str] = mapped_column(VARCHAR(200))\n'
     '    description: Mapped[str | None] = mapped_column(Text, nullable=True)\n'
     '    trimestre: Mapped[int] = mapped_column(SmallInteger)\n'
     '    annee: Mapped[int] = mapped_column(Integer)\n'
     '    statut: Mapped[str] = mapped_column(VARCHAR(20), default="En cours")\n'
     '    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.now)\n'
     '\n'
     'class ObjectifKr(Base):\n'
     '    """PATCH 10 — résultat clé d\'un objectif (avancement 0-100 %)."""\n'
     '    __tablename__ = "objectif_krs"\n'
     '    id: Mapped[int] = mapped_column(primary_key=True)\n'
     '    objectif_id: Mapped[int] = mapped_column(ForeignKey("objectifs.id"))\n'
     '    libelle: Mapped[str] = mapped_column(VARCHAR(200))\n'
     '    avancement: Mapped[int] = mapped_column(SmallInteger, default=0)\n'),
])

# ---------------------------------------------- main.py : nouveau routeurs
edit("backend/app/main.py", [
    (r'from app\.api import \(\n    auth, campagnes, dashboard, espace, evaluations, health, navigation,\n    notifications, notations, referentiel,\n\)',
     'from app.api import (\n'
     '    auth, campagnes, dashboard, espace, evaluations, health, navigation,\n'
     '    notifications, notations, referentiel,\n'
     '    bench, checkins, exports, objectifs, relances, signatures,   # PATCH 10\n'
     ')'),
    (r'app\.include_router\(espace\.router\)           # M2 Mon espace',
     'app.include_router(espace.router)           # M2 Mon espace\n'
     'app.include_router(signatures.router)     # PATCH 10 : signatures N/N+1/N+2\n'
     'app.include_router(checkins.router)       # PATCH 10 : check-ins trimestriels\n'
     'app.include_router(objectifs.router)      # PATCH 10 : objectifs OKR\n'
     'app.include_router(relances.router)       # PATCH 10 : relances retardataires\n'
     'app.include_router(exports.router)        # PATCH 10 : exports Excel/PDF\n'
     'app.include_router(bench.router)         # PATCH 10 : benchmark anonymisé'),
])

# ---------------------------------------------- routes frontend
edit("frontend/src/router/index.js", [
    (r"  \{ path: '/dashboard', name: 'dashboard', component: \(\) => import\('\.\./views/DashboardView\.vue'\) \},\n\]",
     "  { path: '/dashboard', name: 'dashboard', component: () => import('../views/DashboardView.vue') },\n"
     "  { path: '/checkins', name: 'checkins', component: () => import('../views/CheckinsView.vue') },\n"
     "  { path: '/objectifs', name: 'objectifs', component: () => import('../views/ObjectifsView.vue') },\n"
     "  { path: '/benchmark', name: 'benchmark', component: () => import('../views/BenchmarkView.vue') },\n]"),
    (r"  if \(to\.name === 'referentiel' \|\| to\.name === 'campagnes' \|\| to\.name === 'dashboard'\) \{",
     "  if (to.name === 'benchmark' && !auth.isAdmin) return { name: 'espace' }   // PATCH 10\n"
     "  if (to.name === 'referentiel' || to.name === 'campagnes' || to.name === 'dashboard') {"),
])

# ---------------------------------------------- App.vue : menus + sombre + tour
edit("frontend/src/App.vue", [
    (r"import \{ LogOut, LayoutGrid, Compass, ClipboardList, Settings, CalendarCheck, BarChart3, Menu, X \} from 'lucide-vue-next'",
     "import { LogOut, LayoutGrid, Compass, ClipboardList, Settings, CalendarCheck, BarChart3, Menu, X,\n"
     "  MessageSquare, Target, TrendingUp, Moon, Sun } from 'lucide-vue-next'"),
    (r"import ConfirmDialog from './components/ConfirmDialog.vue'",
     "import ConfirmDialog from './components/ConfirmDialog.vue'\n"
     "import TourGuide from './components/TourGuide.vue'   // PATCH 10"),
    (r"const route = useRoute\(\)",
     "const route = useRoute()\n"
     "// PATCH 10 — mode sombre (préférence persistée)\n"
     "const themeSombre = ref(localStorage.getItem('themeSombre') === '1')\n"
     "function basculerTheme() {\n"
     "  themeSombre.value = !themeSombre.value\n"
     "  localStorage.setItem('themeSombre', themeSombre.value ? '1' : '0')\n"
     "  document.documentElement.dataset.theme = themeSombre.value ? 'dark' : ''\n"
     "}"),
    (r"  referentiel: Settings, campagnes: CalendarCheck, dashboard: BarChart3,\n\}",
     "  referentiel: Settings, campagnes: CalendarCheck, dashboard: BarChart3,\n"
     "  checkins: MessageSquare, objectifs: Target, benchmark: TrendingUp,\n}"),
    (r"  l\.push\(\{ to: '/navigation', label: 'NAVIGATION', key: 'navigation' \}\)",
     "  l.push({ to: '/navigation', label: 'NAVIGATION', key: 'navigation' })\n"
     "  l.push({ to: '/checkins', label: 'CHECK-INS', key: 'checkins' })        // PATCH 10\n"
     "  l.push({ to: '/objectifs', label: 'OBJECTIFS', key: 'objectifs' })"),
    (r"    l\.push\(\{ to: '/dashboard', label: 'TABLEAUX DE BORD', key: 'dashboard' \}\)",
     "    l.push({ to: '/dashboard', label: 'TABLEAUX DE BORD', key: 'dashboard' })\n"
     "    l.push({ to: '/benchmark', label: 'BENCHMARK', key: 'benchmark' })"),
    (r"onMounted\(async \(\) => \{\n  if \(auth\.isConnected\) \{",
     "onMounted(async () => {\n"
     "  document.documentElement.dataset.theme = themeSombre.value ? 'dark' : ''   // PATCH 10\n"
     "  if (auth.isConnected) {"),
    (r'      <div class="topbar-brand">EVALPOINT</div>\n',
     '      <div class="topbar-brand">EVALPOINT</div>\n'
     '      <button class="topbar-toggle" :title="themeSombre ? \'Passer en mode clair\' : \'Passer en mode sombre\'" @click="basculerTheme">\n'
     '        <Sun v-if="themeSombre" :size="18" /><Moon v-else :size="18" />\n'
     '      </button>\n'),
    (r'  <div class="app">\n',
     '  <div class="app">\n'
     '    <TourGuide v-if="showSidebar" />   <!-- PATCH 10 : onboarding -->\n'),
])

# ---------------------------------------------- fiche : avancement + signature
edit("frontend/src/views/FicheEvaluationView.vue", [
    (r"const observation = ref\(''\)",
     "const observation = ref('')\n"
     "const signatures = ref([])   // PATCH 10 — signatures électroniques"),
    (r"async function charger\(\) \{\n  fiche\.value = \(await api\.get\('/evaluations/' \+ route\.params\.evaluationId\)\)\.data\n  if \(!onglet\.value\) onglet\.value = fiche\.value\.profils\[0\]\?\.profil_id \|\| null\n\}",
     "async function charger() {\n"
     "  fiche.value = (await api.get('/evaluations/' + route.params.evaluationId)).data\n"
     "  if (!onglet.value) onglet.value = fiche.value.profils[0]?.profil_id || null\n"
     "  try { signatures.value = (await api.get('/evaluations/' + route.params.evaluationId + '/signatures')).data } catch { signatures.value = [] }\n"
     "}"),
    (r'const COLONNES = \[',
     "/* PATCH 10 — auto-éval assistée : barre d'avancement de MON étape */\n"
     "const totalMonEtape = computed(() => (fiche.value?.profils || []).length)\n"
     "const reponduesMonEtape = computed(() => {\n"
     "  const etape = etapeCourante.value\n"
     "  return (fiche.value?.profils || []).filter(l => etape === 'N' ? l.auto_libelle : l.eval_libelle).length\n"
     "})\n"
     "const avancement = computed(() => totalMonEtape.value ? Math.round(100 * reponduesMonEtape.value / totalMonEtape.value) : 0)\n"
     "const peutSigner = computed(() => {\n"
     "  const e = fiche.value?.entete, m = fiche.value?.mon_etape\n"
     "  if (!e || !m || m === 'ADMIN') return false\n"
     "  if (m === 'N' && e.statut_n === 'Clôturée') return !signatures.value.some(s => s.etape === 'N')\n"
     "  if (m === 'N+1' && e.statut_n1 === 'Clôturée') return !signatures.value.some(s => s.etape === 'N+1')\n"
     "  if (m === 'N+2' && e.statut_global === 'Approuvé') return !signatures.value.some(s => s.etape === 'N+2')\n"
     "  return false\n"
     "})\n"
     "async function signerMonEtape() {\n"
     "  const ok = await confirm({\n"
     "    title: 'Signer électroniquement',\n"
     "    message: 'Je certifie avoir pris connaissance de cette fiche et appose ma signature électronique (horodatée, empreinte SHA-256).',\n"
     "    confirmLabel: 'SIGNER',\n"
     "  })\n"
     "  if (!ok) return\n"
     "  try {\n"
     "    await api.post('/evaluations/' + route.params.evaluationId + '/signer')\n"
     "    await charger()\n"
     "    message.value = 'Étape signée électroniquement.'\n"
     "  } catch (e) { erreur.value = e.response?.data?.detail }\n"
     "}\n"
     "\n"
     "const COLONNES = ["),
    (r'(<span class="badge-warn">GLOBAL : \{\{ fiche\.entete\.statut_global \}\}</span>\n      </div>)',
     r'''\1
      <!-- PATCH 10 — barre d'avancement + signatures -->
      <div v-if="fiche.mon_etape && fiche.mon_etape !== 'ADMIN'" style="margin-top:8px;">
        <div style="font-size:11px; font-weight:700; color:var(--color-text-muted);">
          AVANCEMENT {{ fiche.mon_etape }} : {{ avancement }} % ({{ reponduesMonEtape }}/{{ totalMonEtape }})
        </div>
        <div style="height:8px; background:var(--color-border); border-radius:4px; overflow:hidden;">
          <div :style="{ width: avancement + '%' }" style="height:100%; background:var(--color-vert); transition:width .3s;"></div>
        </div>
      </div>
      <div v-if="signatures.length || peutSigner" style="margin-top:8px; display:flex; flex-wrap:wrap; gap:8px; align-items:center;">
        <span v-for="s in signatures" :key="s.id" class="badge-warn" :title="'Empreinte SHA-256 : ' + s.empreinte">
          SIGNÉ {{ s.etape }} — {{ s.auteur }} le {{ s.date }}
        </span>
        <button v-if="peutSigner" class="btn" title="Apposer ma signature électronique (horodatée + empreinte)" @click="signerMonEtape">SIGNER MON ÉTAPE</button>
      </div>'''),
])

# ---------------------------------------------- campagnes : exports + relances
edit("frontend/src/views/CampagnesView.vue", [
    (r"import \{ PlayCircle, FilePlus2, RotateCcw, Lock \} from 'lucide-vue-next'",
     "import { PlayCircle, FilePlus2, RotateCcw, Lock, FileSpreadsheet, Printer, BellRing } from 'lucide-vue-next'"),
    (r'function famillesCochees\(\) \{ return Object\.keys\(familles\.value\)\.filter\(k => familles\.value\[k\]\)\.map\(Number\(\)\) \}',
     "/* PATCH 10 — exports Excel/PDF + relances retardataires */\n"
     "async function exporter(c, format) {\n"
     "  erreur.value = ''\n"
     "  try {\n"
     "    const rep = await api.get('/exports/campagne/' + c.id + '/' + format, { responseType: 'blob' })\n"
     "    const url = URL.createObjectURL(rep.data)\n"
     "    if (format === 'pdf') { window.open(url, '_blank') }\n"
     "    else {\n"
     "      const a = document.createElement('a')\n"
     "      a.href = url; a.download = 'campagne_' + c.id + '.xlsx'; a.click()\n"
     "      URL.revokeObjectURL(url)\n"
     "    }\n"
     "  } catch (e) { erreur.value = e.response?.data?.detail || 'Export impossible.' }\n"
     "}\n"
     "async function relancer(c) {\n"
     "  const ok = await confirm({\n"
     "    title: 'Envoyer les relances',\n"
     "    message: `Notifier tous les retardataires de « ${c.nom} » (badge cloche) ? Un même salarié n'est pas relancé deux fois en 24 h sur la même fiche.`,\n"
     "    confirmLabel: 'ENVOYER', danger: true,\n"
     "  })\n"
     "  if (!ok) return\n"
     "  try {\n"
     "    const r = (await api.post('/relances/campagne/' + c.id + '/envoyer')).data\n"
     "    message.value = 'Relances : ' + r.notifiees + ' notification(s) envoyée(s), '\n"
     "      + r.deja_relancees + ' ignorée(s) (anti-spam 24 h) — N:' + r.n + ' N+1:' + r.n1 + ' N+2:' + r.n2\n"
     "  } catch (e) { erreur.value = e.response?.data?.detail }\n"
     "}\n"
     "\n"
     "function famillesCochees() { return Object.keys(familles.value).filter(k => familles.value[k]).map(Number()) }"),
    (r'(@click="action\(c, \'generer\', \{ familles: famillesCochees\(\), rattrapage: true \}\)"><RotateCcw :size="16" /></button>)',
     r'''\1
            <button class="icon-btn" style="color: var(--color-orange)"
              title="Relancer tous les retardataires de la campagne (badge cloche, anti-spam 24 h)"
              @click="relancer(c)"><BellRing :size="16" /></button>'''),
    (r'(          </template>\n        </td>)',
     r'''          </template>
          <template v-if="c.statut !== 'Brouillon'">
            <button class="icon-btn" style="color: var(--color-vert)"
              title="Exporter toutes les fiches de la campagne en Excel (statuts, décision, signatures)"
              @click="exporter(c, 'excel')"><FileSpreadsheet :size="16" /></button>
            <button class="icon-btn"
              title="Document PDF prêt à imprimer (Ctrl+P puis Enregistrer en PDF)"
              @click="exporter(c, 'pdf')"><Printer :size="16" /></button>
          </template>
        </td>'''),
])
PYEOF

echo "== PATCH 10 : mode sombre (style.css) =="

if grep -q "PATCH 10" frontend/src/style.css; then
  echo "  = frontend/src/style.css (déjà appliqué)"
else
  cat >> frontend/src/style.css <<'EOF'

/* =========================================================================
   PATCH 10 — MODE SOMBRE (tokens [data-theme="dark"]) + bascule topbar.
   ========================================================================= */
[data-theme="dark"] {
  --color-brand: #3B82F6;
  --color-brand-dark: #60A5FA;
  --color-brand-light: #1E3A5F;
  --color-bg: #0F172A;
  --color-surface: #1E293B;
  --color-border: #334155;
  --color-text: #E2E8F0;
  --color-text-muted: #94A3B8;
  --color-vert-bg: #14532D;
  --color-orange-bg: #78350F;
  --color-rouge-bg: #7F1D1D;
  --color-arret-bg: #334155;
  --shadow-card: 0 1px 3px rgba(0, 0, 0, .5);
}
[data-theme="dark"] input, [data-theme="dark"] select, [data-theme="dark"] textarea {
  background: #0F172A; color: var(--color-text); border-color: #334155;
}
[data-theme="dark"] table.data th { background: #263449; color: #E2E8F0; }
[data-theme="dark"] table.data td, [data-theme="dark"] table.data th { border-color: #334155; }
[data-theme="dark"] .card, [data-theme="dark"] .forme { background: var(--color-surface); }
.topbar-toggle { background: none; border: none; cursor: pointer; margin-left: 8px;
  padding: 4px; border-radius: 8px; color: inherit; display: inline-flex; align-items: center; }
.topbar-toggle:hover { opacity: .8; }
EOF
  echo "  + frontend/src/style.css (mode sombre ajouté)"
fi

echo "== PATCH 10 : migration base de données =="
if ( cd backend && python3 - <<'PYEOF'
# -*- coding: utf-8 -*-
from app.core.database import Base, engine
from app.models import rating   # noqa: F401 — enregistre les modèles PATCH 10
Base.metadata.create_all(bind=engine)
print("  Tables signatures / checkins / objectifs / objectif_krs vérifiées (créées si absentes).")
PYEOF
); then
  echo "  Migration OK."
else
  echo "  !! Migration automatique impossible (venv backend actif ?). SQL manuel (psql) :"
  cat <<'SQLEOF'
CREATE TABLE IF NOT EXISTS signatures (
  id SERIAL PRIMARY KEY,
  evaluation_id INTEGER NOT NULL REFERENCES evaluations(id),
  etape VARCHAR(4) NOT NULL,
  auteur_id INTEGER NOT NULL REFERENCES salaries(id),
  empreinte VARCHAR(64) NOT NULL,
  horodatage TIMESTAMPTZ DEFAULT now(),
  UNIQUE (evaluation_id, etape));
CREATE TABLE IF NOT EXISTS checkins (
  id SERIAL PRIMARY KEY,
  salarie_id INTEGER NOT NULL REFERENCES salaries(id),
  auteur_id INTEGER NOT NULL REFERENCES salaries(id),
  trimestre SMALLINT NOT NULL,
  annee INTEGER NOT NULL,
  points_forts TEXT NOT NULL,
  axes_amelioration TEXT NOT NULL,
  decision VARCHAR(20) DEFAULT 'En cours',
  date_reunion DATE,
  created_at TIMESTAMPTZ DEFAULT now());
CREATE TABLE IF NOT EXISTS objectifs (
  id SERIAL PRIMARY KEY,
  salarie_id INTEGER NOT NULL REFERENCES salaries(id),
  auteur_id INTEGER NOT NULL REFERENCES salaries(id),
  titre VARCHAR(200) NOT NULL,
  description TEXT,
  trimestre SMALLINT NOT NULL,
  annee INTEGER NOT NULL,
  statut VARCHAR(20) DEFAULT 'En cours',
  created_at TIMESTAMPTZ DEFAULT now());
CREATE TABLE IF NOT EXISTS objectif_krs (
  id SERIAL PRIMARY KEY,
  objectif_id INTEGER NOT NULL REFERENCES objectifs(id),
  libelle VARCHAR(200) NOT NULL,
  avancement SMALLINT DEFAULT 0);
SQLEOF
fi

echo ""
echo "============================================================"
echo " PATCH 10 appliqué. RECETTE :"
echo "  1. Relancer backend (uvicorn) + frontend (npm run dev)."
echo "  2. FICHE : barre d'avancement de son étape ; clôturer son étape"
echo "     puis SIGNER MON ÉTAPE -> badge « SIGNÉ N — nom le … » (empreinte"
echo "     au survol). N+2 signe après approbation."
echo "  3. CAMPAGNES (Admin) : icônes EXPORT EXCEL / PDF + BELLRING (relances)"
echo "     sur une campagne Ouverte ; relancer 2x -> anti-spam 24 h."
echo "  4. CHECK-INS : créer un check-in pour un collaborateur, le clôturer."
echo "  5. OBJECTIFS : créer un objectif, ajouter des résultats clés,"
echo "     avancement +/- 10 %."
echo "  6. BENCHMARK (Admin) : agrégats par section, < 5 fiches anonymisées."
echo "  7. Mode sombre : lune/soleil dans la topbar (persisté)."
echo "  8. Onboarding : vider localStorage 'tourFait' pour revoir la visite."
echo "  9. Relances automatiques quotidiennes (optionnel) :"
echo "       crontab -e  ->  0 8 * * * cd /opt/rating-dev/backend && \\"
echo "         ./venv/bin/python relances_cron.py >> relances.log 2>&1"
echo " 10. PDF : le bouton ouvre un document imprimable ; Ctrl+P ->"
echo "     « Enregistrer au format PDF » (aucune dépendance PDF nécessaire)."
echo "============================================================"