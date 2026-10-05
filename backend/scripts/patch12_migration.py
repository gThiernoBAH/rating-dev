# PATCH 12 — migration DB (idempotente). Lancer depuis backend/ avec le venv :
#   .venv/bin/python scripts/patch12_migration.py
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
try:
    from app.core.database import engine
except ImportError:  # secours
    from app.core.database import SessionLocal
    engine = SessionLocal.kw["bind"]
from sqlalchemy import text

SQL = [
    "ALTER TABLE sites ADD COLUMN IF NOT EXISTS actif boolean NOT NULL DEFAULT true",
    "ALTER TABLE departements ADD COLUMN IF NOT EXISTS actif boolean NOT NULL DEFAULT true",
    "ALTER TABLE sections ADD COLUMN IF NOT EXISTS actif boolean NOT NULL DEFAULT true",
    "ALTER TABLE emplois ADD COLUMN IF NOT EXISTS actif boolean NOT NULL DEFAULT true",
    "ALTER TABLE categories ADD COLUMN IF NOT EXISTS actif boolean NOT NULL DEFAULT true",
    "ALTER TABLE postes ADD COLUMN IF NOT EXISTS actif boolean NOT NULL DEFAULT true",
    "ALTER TABLE criteres ADD COLUMN IF NOT EXISTS editable boolean NOT NULL DEFAULT false",
    "ALTER TABLE critere_details ADD COLUMN IF NOT EXISTS sens smallint NOT NULL DEFAULT 1",
    "ALTER TABLE critere_details ADD COLUMN IF NOT EXISTS valeur_min numeric(5,2)",
    "ALTER TABLE critere_details ADD COLUMN IF NOT EXISTS valeur_max numeric(5,2)",
    "ALTER TABLE critere_details ADD COLUMN IF NOT EXISTS actif boolean NOT NULL DEFAULT true",
    "ALTER TABLE critere_details ALTER COLUMN critere_id DROP NOT NULL",
    "ALTER TABLE salaries ADD COLUMN IF NOT EXISTS nature varchar(20) NOT NULL DEFAULT 'Embauché'",
    "ALTER TABLE evaluation_lignes ADD COLUMN IF NOT EXISTS valeur_choisie numeric(5,2)",
    """CREATE TABLE IF NOT EXISTS evaluation_criteres (
        id serial PRIMARY KEY,
        evaluation_id integer NOT NULL REFERENCES evaluations(id),
        critere_id integer NOT NULL REFERENCES criteres(id),
        libelle varchar(300) NOT NULL,
        UNIQUE (evaluation_id, critere_id)
    )""",
    # Détails à intervalle (legacy SENS=2) : 7-9 / 10-12 / 13-15 / 16-18 / 19-20
    "UPDATE critere_details SET sens=2, valeur_min=7,  valeur_max=9  WHERE sens=1 AND lower(trim(libelle_descriptif))='très insatisfaisant'",
    "UPDATE critere_details SET sens=2, valeur_min=10, valeur_max=12 WHERE sens=1 AND lower(trim(libelle_descriptif))='a améliorer'",
    "UPDATE critere_details SET sens=2, valeur_min=13, valeur_max=15 WHERE sens=1 AND lower(trim(libelle_descriptif))='satisfaisant'",
    "UPDATE critere_details SET sens=2, valeur_min=16, valeur_max=18 WHERE sens=1 AND lower(trim(libelle_descriptif))='excellent'",
    "UPDATE critere_details SET sens=2, valeur_min=19, valeur_max=20 WHERE sens=1 AND lower(trim(libelle_descriptif))='top performer'",
]
with engine.begin() as con:
    for s in SQL:
        con.execute(text(s))
print("MIGRATION PATCH 12 OK (actif x6, editable, sens/min/max/actif détails, nature, "
      "valeur_choisie, table evaluation_criteres, intervalles 7-9/10-12/13-15/16-18/19-20).")
