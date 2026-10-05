# PATCH 13 — dédoublonnage des fiches + index unique (idempotent).
# À lancer DEPUIS backend/ (le .env s'y trouve) :
#   python scripts/patch13_migration.py
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from app.core.database import engine
from sqlalchemy import text

# Tables filles à purger avant de supprimer une fiche doublon
TABLES_FILLES = [
    "evaluation_lignes",
    "evaluation_criteres",   # PATCH 12 (peut ne pas exister encore)
    "signatures",            # PATCH 10
    "approbations",
    "notifications",
]

with engine.begin() as con:
    groupes = con.execute(text(
        "SELECT campagne_id, salarie_id, count(*) FROM evaluations "
        "GROUP BY 1, 2 HAVING count(*) > 1")).fetchall()
    print(f"{len(groupes)} groupe(s) de fiches en doublon détecté(s).")
    total = 0
    for camp, sal, n in groupes:
        ids = [r[0] for r in con.execute(text(
            "SELECT id FROM evaluations WHERE campagne_id=:c AND salarie_id=:s ORDER BY id"),
            {"c": camp, "s": sal}).fetchall()]
        # gardon = la fiche avec le plus de lignes saisies (tie-break : id le plus bas)
        def nb_lignes(i):
            try:
                return con.execute(text(
                    "SELECT count(*) FROM evaluation_lignes WHERE evaluation_id=:i"),
                    {"i": i}).scalar() or 0
            except Exception:
                return 0
        keeper = sorted(ids, key=lambda i: (-nb_lignes(i), i))[0]
        losers = [i for i in ids if i != keeper]
        for i in losers:
            for t in TABLES_FILLES:
                try:
                    con.execute(text(f"DELETE FROM {t} WHERE evaluation_id=:i"), {"i": i})
                except Exception:
                    pass  # table absente ou colonne absente : on continue
            con.execute(text("DELETE FROM evaluations WHERE id=:i"), {"i": i})
        print(f"  campagne {camp} / salarié {sal} : garde fiche {keeper}, supprime {losers}")
        total += len(losers)
    # Index unique : empêche tout nouveau doublon (génération idempotente garantie)
    con.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS uq_evaluations_campagne_salarie "
                     "ON evaluations (campagne_id, salarie_id)"))
    print(f"{total} fiche(s) doublon(s) supprimée(s). Index unique créé/vérifié.")
