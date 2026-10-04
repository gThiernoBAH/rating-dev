#!/usr/bin/env bash
# ============================================================================
# PATCH 7 — EVALPOINT (rating-dev) — 04/10/2026
# Alignement UX vusine-dev :
#   1. Login compact (carte 360px, champs 42px)
#   2. Onglets .tabs alignés à gauche
#   3. M5 Salariés : badge Actif vert/rouge, champs ADMIN + ACTIF dans la
#      fiche, suppression de l'icône toggle (et de basculerActif)
#   4. Backend : update_salarie protégé (Admin ne peut pas se rétrograder /
#      se désactiver lui-même ; au moins un Admin requis) + bug corrigé :
#      le PUT n'écrase plus is_active/is_admin par les valeurs par défaut.
#      Navigation : comptes Admin exclus de la liste des salariés.
#   5. M6 Campagnes : lignes compactes (actions en icônes + hints, familles
#      en colonne, statut en badge)
#
# Usage : à la racine du projet rating-dev/ (contient backend/ et frontend/) :
#   bash patch7.sh
# ============================================================================
set -euo pipefail

if [ ! -d backend/app ] || [ ! -d frontend/src ]; then
  echo "ERREUR : lancez ce script depuis la racine de rating-dev/ (backend/ et frontend/ attendus)."
  exit 1
fi

# --- sauvegardes ---
for f in frontend/src/views/LoginView.vue frontend/src/views/ReferentielView.vue \
         frontend/src/views/CampagnesView.vue frontend/src/App.vue \
         frontend/src/style.css backend/app/api/referentiel.py \
         backend/app/api/navigation.py; do
  cp "$f" "$f.bak-patch7"
done

python3 - <<'PYEOF'
# -*- coding: utf-8 -*-
"""PATCH 7 — vérifie chaque motif AVANT d'écrire ; abandon propre si absent."""
import re, sys, pathlib

OK = []

def edit(path, repls, full=None):
    p = pathlib.Path(path)
    src = p.read_text(encoding="utf-8")
    for pat, rep in repls:
        src, n = re.subn(pat, rep, src, count=1, flags=re.S)
        if n != 1:
            print(f"ERREUR : motif introuvable dans {path} :\n  {pat[:100]}")
            sys.exit(1)
    p.write_text(full if full is not None else src, encoding="utf-8")
    OK.append(path)

# ---------------------------------------------------------------- 1. Login
LOGIN_STYLE = """<style scoped>
.login-page {
  height: 100%; width: 100%;
  display: flex; align-items: center; justify-content: center;
  background: var(--color-bg); padding: var(--space-4);
}
.login-card {
  width: 100%; max-width: 360px;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-card);
  padding: var(--space-6) var(--space-5);
}
.brand { display: flex; align-items: center; gap: var(--space-2); margin-bottom: var(--space-5); }
.brand-icon {
  width: 40px; height: 40px; border-radius: var(--radius-md);
  background: var(--color-brand); color: var(--color-text-inverse);
  display: flex; align-items: center; justify-content: center; flex-shrink: 0;
}
.brand-name { font-size: var(--font-size-lg); font-weight: 800; letter-spacing: 1px; color: var(--color-brand-dark); }
.brand-sub { font-size: var(--font-size-xs); color: var(--color-text-muted); }
.login-form { display: flex; flex-direction: column; gap: var(--space-3); }
.field { display: flex; flex-direction: column; gap: 2px; }
.field-label { font-size: var(--font-size-xs); font-weight: 600; color: var(--color-text-muted); }
.input-group { position: relative; display: flex; align-items: center; }
.input-icon { position: absolute; left: 12px; color: var(--color-text-muted); pointer-events: none; }
.input-group input {
  height: 42px;
  padding: 0 var(--space-3) 0 38px;
  font-size: var(--font-size-sm);
}
.toggle-pwd {
  position: absolute; right: 10px; background: none; border: none;
  color: var(--color-text-muted); cursor: pointer; display: flex; padding: var(--space-1);
}
.error-message { color: var(--color-rouge); font-size: var(--font-size-xs); margin: 0; }
.submit-btn {
  height: 42px; margin-top: var(--space-1);
  border: none; border-radius: var(--radius-md);
  background: var(--color-brand); color: var(--color-text-inverse);
  font-size: var(--font-size-sm); font-weight: 700; cursor: pointer;
  transition: background .15s;
}
.submit-btn:hover:not(:disabled) { background: var(--color-brand-dark); }
.submit-btn:disabled { opacity: .6; cursor: not-allowed; }
.mdp-titre { margin: 0 0 var(--space-2); font-size: var(--font-size-base); color: var(--color-brand-dark); }
.mdp-texte { font-size: var(--font-size-xs); color: var(--color-text-muted); margin: 0 0 var(--space-4); line-height: 1.4; }
</style>
"""
edit("frontend/src/views/LoginView.vue",
     [(r"<style scoped>.*$", LOGIN_STYLE)])

# ------------------------------------------------- 2. App.vue : onglets gauche
edit("frontend/src/App.vue",
     [(r"border-bottom: 1px solid var\(--color-border\); justify-content: center; \}",
       "border-bottom: 1px solid var(--color-border); justify-content: flex-start; }")])

# ------------------------------------------------- 2b. style.css : badge-statut
p = pathlib.Path("frontend/src/style.css")
css = p.read_text(encoding="utf-8")
if ".badge-statut" not in css:
    css += """
/* PATCH 7 — badge de statut compact (Actif/Inactif, statut campagne) */
.badge-statut { display: inline-block; padding: 2px 10px; border-radius: 999px; font-size: 11px; font-weight: 700; white-space: nowrap; }
"""
    p.write_text(css, encoding="utf-8")
OK.append("frontend/src/style.css")

# ------------------------------------ 3. ReferentielView.vue (5 modifications)
edit("frontend/src/views/ReferentielView.vue", [
    # 3a. imports lucide
    (r"import \{ Pencil, Trash2, Plus, UserCheck, UserX \} from 'lucide-vue-next'",
     "import { Pencil, Trash2, Plus } from 'lucide-vue-next'"),
    # 3b. suppression de basculerActif
    (r"\nasync function basculerActif\(s\) \{.*?\n\}\n\n", "\n"),
    # 3c-1. valeurs par défaut du formulaire salarié
    (r"n1_id: null, hors_evaluation: false \}",
     "n1_id: null, hors_evaluation: false,\n    is_admin: false, is_active: true }"),
    # 3c-2. corps envoyé au PUT
    (r"n1_id: f\.n1_id \|\| null, hors_evaluation: !!f\.hors_evaluation \}",
     "n1_id: f.n1_id || null, hors_evaluation: !!f.hors_evaluation,\n        is_admin: !!f.is_admin, is_active: f.is_active !== false }"),
    # 3c-3. champs ADMIN + ACTIF dans la fiche
    (r'(<input type="checkbox" v-model="forme\.hors_evaluation"[^>]*/></div>)',
     r"""\1
          <div class="field"><label>ADMINISTRATEUR</label>
            <input type="checkbox" v-model="forme.is_admin" style="width:auto"
              title="Compte Administrateur : accès au paramétrage, campagnes et tableaux de bord. Exclu des évaluations et statistiques." /></div>
          <div class="field"><label>ACTIF</label>
            <input type="checkbox" v-model="forme.is_active" style="width:auto"
              title="Compte actif : le salarié peut se connecter. Décoché : connexion refusée (fiches existantes conservées)." /></div>"""),
    # 3d. badge vert/rouge dans la colonne Actif
    (r'<template #cell-actions="\{ row \}">',
     """<template #cell-actif_aff="{ row }">
        <span class="badge-statut" :class="row.is_active ? 'statut-vert' : 'statut-rouge'">
          {{ row.is_active ? 'Actif' : 'Inactif' }}
        </span>
      </template>
      <template #cell-actions="{ row }">"""),
    # 3e. suppression du bouton toggle dans Actions
    (r'\s*<button v-if="onglet === \'salaries\'" class="icon-btn".*?</button>', ""),
])

# --------------------------------------------- 4a. referentiel.py update_salarie
NEW_UPDATE = '''@router.put("/salaries/{salarie_id}", response_model=SalarieOut)
def update_salarie(salarie_id: int, p: SalarieIn, db: Session = Depends(get_db),
                   admin: Salarie = Depends(require_admin)):
    obj = db.query(Salarie).get(salarie_id)
    if not obj:
        raise HTTPException(404, "Introuvable.")
    if salarie_id == p.n1_id:
        raise HTTPException(422, "Un salarié ne peut être son propre N+1.")
    if salarie_id == admin.id:
        # Un Admin ne peut ni se rétrograder ni se désactiver lui-même.
        if obj.is_admin and not p.is_admin:
            raise HTTPException(422, "Vous ne pouvez pas retirer votre propre statut Admin.")
        if obj.is_active and not p.is_active:
            raise HTTPException(422, "Vous ne pouvez pas désactiver votre propre compte.")
    # Ne pas retirer le statut Admin du dernier Administrateur.
    if obj.is_admin and not p.is_admin and \\
            db.query(Salarie).filter(Salarie.is_admin.is_(True)).count() <= 1:
        raise HTTPException(422, "Il doit rester au moins un compte Administrateur.")
    for k, v in p.model_dump().items():
        setattr(obj, k, v)
    db.commit(); db.refresh(obj)
    return obj


@router.delete("/salaries/{salarie_id}"'''
edit("backend/app/api/referentiel.py",
     [(r'@router\.put\("/salaries/\{salarie_id\}", response_model=SalarieOut\)\ndef update_salarie\(.*?\n\n\n@router\.delete\("/salaries/\{salarie_id\}"',
       NEW_UPDATE)])

# ------------------------------------------ 4b. navigation.py : exclure les Admins
edit("backend/app/api/navigation.py", [
    (r"salaries = db\.query\(Salarie\)\.filter\(Salarie\.is_active\.is_\(True\)\)\.all\(\)",
     "salaries = db.query(Salarie).filter(Salarie.is_active.is_(True),\n"
     "                                            Salarie.is_admin.is_(False)).all()"),
    (r"\.filter\(Salarie\.id\.in_\(ids\)\)\.all\(\)",
     ".filter(Salarie.id.in_(ids),\n"
     "                                       Salarie.is_admin.is_(False)).all()"),
])

# ------------------------------------------------- 5. CampagnesView.vue complet
CAMPAGNES = '''<!-- 2026-10-04 PATCH 7 — M6 : lignes campagnes compactes (actions en icônes
     avec hints), familles en cases resserrées (colonne dédiée), statut en badge. -->
<script setup>
import { onMounted, ref } from 'vue'
import { PlayCircle, FilePlus2, RotateCcw, Lock } from 'lucide-vue-next'
import api from '../api/client'
import { useConfirm } from '../composables/useConfirm'

const { confirm } = useConfirm()
const campagnes = ref([])
const message = ref('')
const erreur = ref('')
const forme = ref({ nom: '', exercice: new Date().getFullYear(), date_ouverture: '', date_cloture: '' })
const familles = ref({ 1: true, 2: true, 3: true })

async function charger() { campagnes.value = (await api.get('/campagnes')).data }
onMounted(charger)

async function creer() {
  try {
    await api.post('/campagnes', { ...forme.value,
      date_ouverture: forme.value.date_ouverture, date_cloture: forme.value.date_cloture })
    message.value = 'Campagne créée (Brouillon).'
    await charger()
  } catch (e) { erreur.value = e.response?.data?.detail }
}

async function action(c, act, corps) {
  try {
    const rep = await api.post('/campagnes/' + c.id + '/' + act, corps)
    if (act === 'generer') {
      const r = rep.data
      message.value = 'Génération : ' + r.creees + ' créée(s), ' + r.deja_existantes
        + ' déjà existante(s), ' + r.hors_evaluation + ' hors évaluation, '
        + r.cutoff_exclus + ' exclues (cutoff), sans N+1 : '
        + (r.sans_n1.join(', ') || 'aucun')
    } else { message.value = 'Action effectuée : ' + act }
    await charger()
  } catch (e) { erreur.value = e.response?.data?.detail }
}

async function ouvrir(c) {
  const ok = await confirm({
    title: 'Ouvrir la campagne',
    message: `Ouvrir « ${c.nom} » ? Les salariés pourront ensuite être évalués (fiches générées par famille).`,
    confirmLabel: 'Ouvrir',
  })
  if (ok) await action(c, 'ouvrir', {})
}

async function cloturer(c) {
  const ok = await confirm({
    title: 'Clôturer la campagne',
    message: `Clôturer « ${c.nom} » ? Les fiches non approuvées seront verrouillées et la campagne passera en Clôturée.`,
    danger: true, confirmLabel: 'Clôturer',
  })
  if (ok) await action(c, 'cloturer', {})
}

function famillesCochees() { return Object.keys(familles.value).filter(k => familles.value[k]).map(Number) }

const FAM_LABELS = { 1: 'Cadres', 2: 'AM', 3: 'Empl.-Ouvr.' }
</script>

<template>
  <div>
    <h3>CRÉER UNE CAMPAGNE</h3>
    <div class="forme">
      <div class="field"><label>NOM</label><input v-model="forme.nom" title="Nom de la campagne (unique par exercice)" /></div>
      <div class="field"><label>EXERCICE</label><input type="number" v-model="forme.exercice" title="Exercice budgétaire (ex. 2026)" /></div>
      <div class="field"><label>OUVERTURE</label><input type="date" v-model="forme.date_ouverture" title="Date d'ouverture de la campagne" /></div>
      <div class="field"><label>CLÔTURE</label><input type="date" v-model="forme.date_cloture" title="Date de clôture prévue" /></div>
      <button class="btn" title="Créer la campagne en statut Brouillon" @click="creer">CREER</button>
    </div>
    <div v-if="message" class="ok">{{ message }}</div>
    <div v-if="erreur" class="error">{{ erreur }}</div>

    <table class="data">
      <thead><tr><th>NOM</th><th>EXERCICE</th><th>OUVERTURE</th><th>CLÔTURE</th><th>STATUT</th><th>FAMILLES</th><th>ACTIONS</th></tr></thead>
      <tbody><tr v-for="c in campagnes" :key="c.id">
        <td>{{ c.nom }}</td>
        <td>{{ c.exercice }}</td>
        <td>{{ c.date_ouverture }}</td>
        <td>{{ c.date_cloture }}</td>
        <td><span class="badge-statut"
          :class="c.statut === 'Ouverte' ? 'statut-vert' : c.statut === 'Clôturée' ? 'statut-arret' : 'statut-orange'">{{ c.statut }}</span></td>
        <td>
          <template v-if="c.statut === 'Ouverte'">
            <label v-for="(lib, f) in FAM_LABELS" :key="f" class="fam"
              :title="'Générer les fiches des ' + lib + ' (famille ' + f + ')'">
              <input type="checkbox" v-model="familles[f]" /> {{ lib }}
            </label>
          </template>
        </td>
        <td class="actions">
          <button v-if="c.statut === 'Brouillon'" class="icon-btn" style="color: var(--color-vert)"
            title="Ouvrir la campagne : elle passe en statut Ouverte"
            @click="ouvrir(c)"><PlayCircle :size="16" /></button>
          <template v-if="c.statut === 'Ouverte'">
            <button class="icon-btn"
              title="Générer les fiches d'évaluation des familles cochées (idempotent)"
              @click="action(c, 'generer', { familles: famillesCochees() })"><FilePlus2 :size="16" /></button>
            <button class="icon-btn"
              title="Générer uniquement les fiches manquantes (nouveaux arrivants, rattrapage)"
              @click="action(c, 'generer', { familles: famillesCochees(), rattrapage: true })"><RotateCcw :size="16" /></button>
            <button class="icon-btn danger" style="margin-left:6px"
              title="Clôturer définitivement la campagne"
              @click="cloturer(c)"><Lock :size="16" /></button>
          </template>
        </td>
      </tr></tbody>
    </table>
  </div>
</template>

<style scoped>
h3 { font-size: 13px; color: var(--color-brand-dark); margin-bottom: 8px; }
.forme { display: flex; gap: 10px; background: var(--color-surface); padding: 14px; border-radius: var(--radius-md); margin-bottom: 12px; flex-wrap: wrap; }
.field { min-width: 160px; }
table.data td { padding: 6px 10px; vertical-align: middle; }
.fam { display: inline-flex; align-items: center; gap: 3px; margin-right: 10px; font-size: 11px; font-weight: 600; color: var(--color-text-muted); cursor: pointer; }
.fam input { width: auto; margin: 0; }
.actions { white-space: nowrap; }
</style>
'''
edit("frontend/src/views/CampagnesView.vue", [], full=CAMPAGNES)

print("OK — fichiers modifiés :")
for f in OK:
    print("  -", f)
PYEOF

echo ""
echo "✅ PATCH 7 appliqué. Sauvegardes : *.bak-patch7 (à supprimer après validation)."
echo "À tester : login compact · onglets à gauche · badge Actif vert/rouge M5 ·"
echo "champs ADMIN/ACTIF dans la fiche salarié · Admin invisible dans Navigation ·"
echo "lignes campagnes compactes. Puis redémarrer uvicorn + npm run dev."