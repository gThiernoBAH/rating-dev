#!/usr/bin/env bash
# ============================================================================
# REPAIR PATCH 8 — v2 (04/10/2026)
# Dédoublonne les insertions dupliquées par une re-exécution du patch8 :
#   - const estMobile dupliqué (App.vue, EspaceView, EvaluationsView, Fiche)
#   - bouton sidebar-close dupliqué (App.vue)
#   - span bandeau mobile dupliqué éventuel (EspaceView)
#   - parenthèse manquante du router.beforeEach
# Robuste : détecte les blocs IDENTIQUES ADJACENTS (le fichier se compare à
# lui-même, aucun texte attendu codé en dur). Idempotent.
#
# Usage : à la racine de rating-dev/ :
#   bash repair-patch8.sh
# ============================================================================
set -euo pipefail

python3 - <<'PYEOF'
# -*- coding: utf-8 -*-
import re, pathlib

def collapse(path, pattern, label):
    p = pathlib.Path(path)
    s = p.read_text(encoding="utf-8")
    s2, n = re.subn(pattern, r"\g<b>", s)
    if n:
        p.write_text(s2, encoding="utf-8")
        print(f"  réparé : {label} ({n} doublon(s) supprimé(s))")
    else:
        print(f"  ok     : {label}")

# Bloc estMobile dupliqué : [commentaire PATCH 8 optionnel] const + listener
ESTMOBILE = (r"(?P<b>(?://[^\n]*PATCH 8[^\n]*\n)?const estMobile[^\n]*\n"
             r"(?:window\.matchMedia[^\n]*\n)?)(?P=b)+")
collapse("frontend/src/App.vue", ESTMOBILE, "App.vue estMobile")
collapse("frontend/src/views/EspaceView.vue", ESTMOBILE, "EspaceView.vue estMobile")
collapse("frontend/src/views/EvaluationsView.vue", ESTMOBILE, "EvaluationsView.vue estMobile")
collapse("frontend/src/views/FicheEvaluationView.vue", ESTMOBILE, "FicheEvaluationView.vue estMobile")

# Bouton fermeture sidebar dupliqué (App.vue, insertion patch 7b)
SIDEBAR_CLOSE = (r"(?P<b>\s*<button class=\"sidebar-close\"[^\n]*\n"
                 r"\s*<X[^\n]*\n\s*</button>\n)(?P=b)+")
collapse("frontend/src/App.vue", SIDEBAR_CLOSE, "App.vue sidebar-close")

# Span bandeau mobile dupliqué éventuel (EspaceView)
SPAN = r"(?P<b>\s*<span v-if=\"estMobile\">[^\n]*</span>\n)(?P=b)+"
collapse("frontend/src/views/EspaceView.vue", SPAN, "EspaceView.vue span mobile")

# Parenthèse fermante du router.beforeEach
p = pathlib.Path("frontend/src/router/index.js")
s = p.read_text(encoding="utf-8")
if "  }\n}\n\nexport default router" in s:
    s = s.replace("  }\n}\n\nexport default router", "  }\n})\n\nexport default router")
    p.write_text(s, encoding="utf-8")
    print("  réparé : router/index.js (parenthèse beforeEach)")
else:
    print("  ok     : router/index.js (parenthèse beforeEach)")

# ---------------- VÉRIFICATION FINALE ----------------
print()
bad = False
for f in ["frontend/src/App.vue", "frontend/src/views/EspaceView.vue",
          "frontend/src/views/EvaluationsView.vue",
          "frontend/src/views/FicheEvaluationView.vue"]:
    c = pathlib.Path(f).read_text(encoding="utf-8").count("const estMobile")
    if c != 1:
        print(f"  ATTENTION : {f} contient {c} 'const estMobile'")
        bad = True
app = pathlib.Path("frontend/src/App.vue").read_text(encoding="utf-8")
if app.count('class="sidebar-close"') != 1:
    print("  ATTENTION : App.vue contient plusieurs sidebar-close")
    bad = True
if not bad:
    print("VÉRIFICATION OK — plus aucun doublon. Relance le frontend.")
PYEOF