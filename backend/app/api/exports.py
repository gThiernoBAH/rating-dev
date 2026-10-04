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
