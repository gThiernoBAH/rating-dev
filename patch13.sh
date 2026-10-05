#!/usr/bin/env bash
# ============================================================================
# PATCH 13 — EVALPOINT (rating-dev) — 2026-10-05 (recette post-patch12)
# À exécuter DEPUIS LA RACINE du dépôt :  bash patch13.sh
# IDEMPOTENT (leçon 9/10/11) : marqueurs littéraux, garde SKIP, ast.parse.
#
# Corrige les 6 points de la recette :
#  1. Menu EVALUATIONS retiré PARTOUT (doublon avec MON ESPACE) — App.vue
#  2. Doublons de fiches en base → dédoublonnage + index unique (migration)
#  3. NAVIGATION : combobox « Toutes les sections » EN PREMIER, salarié ensuite
#  4. Erreur vite fiche (ligne 313) : échappements \' parasites → ' 
#  5. Erreur vite PARAMETRAGE (ligne 496) : commentaires HTML inside-tag retirés
#  6. Idem pour tous les fichiers touchés par patch12 (nettoyage \')
# ============================================================================
set -u
cd "$(dirname "$0")"
echo "=== PATCH 13 — correctifs frontend ==="
python3 - <<'PYEOF'
import re, pathlib

ROOT = pathlib.Path(".")
def rd(p): return (ROOT / p).read_text(encoding="utf-8")
def wr(p, c): (ROOT / p).write_text(c, encoding="utf-8")

# ============ 1. App.vue — retirer ENTIÈREMENT le menu EVALUATIONS ============
p = "frontend/src/App.vue"
c = rd(p)
if "key: 'evaluations'" in c:
    c2 = re.sub(r"\n  if \(\(?auth\.estN1[\s\S]*?key: 'evaluations' \}\)\n  \}\n", "\n", c, count=1)
    assert "key: 'evaluations'" not in c2, "bloc EVALUATIONS non entièrement supprimé — voir App.vue"
    wr(p, c2)
    print("  OK    App.vue :: menu EVALUATIONS retiré (l'écran reste accessible via MON ESPACE)")
else:
    print("  SKIP  App.vue :: menu EVALUATIONS déjà retiré")

# ============ 2. Nettoyage \\' parasites (erreurs vite « Expecting Unicode escape ») ============
for p in ["frontend/src/views/FicheEvaluationView.vue",
          "frontend/src/views/ReferentielView.vue",
          "frontend/src/views/NavigationView.vue"]:
    c = rd(p)
    n = c.count("\\'")
    if n:
        wr(p, c.replace("\\'", "'"))
        print(f"  OK    {p} :: {n} échappement(s) \\' corrigé(s)")
    else:
        print(f"  SKIP  {p} :: aucun échappement parasite")

# ============ 3. Commentaires HTML DANS les balises (erreur « Attribute name cannot contain U+0022 ») ============
p = "frontend/src/views/ReferentielView.vue"
c = rd(p); before = c
# 3a. badge actif
c = c.replace("""class="row.actif !== false ? 'statut-vert' : 'statut-rouge'"   <!-- PATCH 12 -->\n""",
              """class="row.actif !== false ? 'statut-vert' : 'statut-rouge'"\n""")
# 3b. default-sort
c = re.sub(r"""(:default-sort="onglet === 'salaries' \? \{ key: 'admin_tri', dir: 1 \} : null")   <!-- PATCH 12 : Admins en tête -->\n""",
           r"""\1\n""", c)
# 3c. select sens (formulaire critères)
c = c.replace("""style="width:104px"   <!-- PATCH 12 -->\n""", """style="width:104px"\n""")
# 3d. bibliothèque
c = c.replace("""!x.critere_id)"   <!-- PATCH 12 : bibliothèque -->\n""", """!x.critere_id)"\n""")
if c != before:
    wr(p, c)
    print("  OK    ReferentielView.vue :: commentaire(s) inside-tag retiré(s)")
else:
    print("  SKIP  ReferentielView.vue :: aucun commentaire inside-tag")

p = "frontend/src/views/NavigationView.vue"
c = rd(p)
c2 = c.replace("""@change="surFiltreSection"   <!-- PATCH 12 -->\n""", """@change="surFiltreSection"\n""")
if c2 != c:
    wr(p, c2)
    print("  OK    NavigationView.vue :: commentaire inside-tag retiré")
else:
    print("  SKIP  NavigationView.vue :: aucun commentaire inside-tag")

# ============ 4. NAVIGATION — section AVANT salarié dans la barre ============
p = "frontend/src/views/NavigationView.vue"
c = rd(p)
m_sec = re.search(r"\n(      <select v-model=\"filtreSection\"[\s\S]*?</select>)", c)
m_sal = re.search(r"\n(      <select v-model=\"salarieId\"[\s\S]*?</select>)", c)
if m_sec and m_sal and m_sec.start() > m_sal.start():
    sec_block, sal_block = m_sec.group(1), m_sal.group(1)
    c = c[:m_sal.start()] + "\n" + sec_block + "\n" + sal_block + c[m_sec.end():]
    wr(p, c)
    print("  OK    NavigationView.vue :: combobox section placé AVANT le salarié")
elif m_sec and m_sal:
    print("  SKIP  NavigationView.vue :: ordre déjà correct")
else:
    print("  ??    NavigationView.vue :: combobox non trouvés (déjà traité ?)")

print("\n=== PATCH 13 — frontend terminé ===")
PYEOF
[ $? -ne 0 ] && { echo "ÉCHEC frontend."; exit 1; }

# ============================================================================
# MIGRATION DB — dédoublonnage des fiches + index unique
# (les doublons viennent de générations antérieures à l'index unique, qui
#  n'a jamais été créé : la migration patch12 n'avait pas été exécutée)
# ============================================================================
echo "=== PATCH 13 — migration base de données (dédoublonnage fiches) ==="
mkdir -p backend/scripts
cat > backend/scripts/patch13_migration.py <<'MIGEOF'
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
MIGEOF

PY=""
for c in backend/.venv/bin/python .venv/bin/python backend/venv/bin/python; do
  [ -x "$c" ] && PY="$c" && break
done
[ -z "$PY" ] && PY="python"

(cd backend && exec "$PY" scripts/patch13_migration.py) \
  || echo "⚠ Migration en échec — lance-la manuellement : cd backend && python scripts/patch13_migration.py"

echo "=== PATCH 13 terminé. Relance vite (frontend) puis Ctrl+Shift+R dans le navigateur. ==="
echo "=== (le backend n'a pas été modifié par ce patch — pas besoin de le relancer,   ==="
echo "===  sauf si la migration a affiché une erreur)                                ==="