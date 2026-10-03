<!-- 2026-10-02 PATCH2 — M5 : onglets + CRUD complet (ajouter/modifier/supprimer)
     sur les 9 tables du referentiel. Admin seul. -->
<script setup>
import { onMounted, ref } from 'vue'
import api from '../api/client'

const onglet = ref('salaries')
const donnees = ref({})
const message = ref('')
const erreur = ref('')
const forme = ref(null)
const modeEdition = ref(false)

const ONGLETS = ['salaries', 'emplois', 'profils', 'criteres', 'sites',
                 'departements', 'sections', 'categories', 'postes']

async function charger() {
  const cles = ['sites', 'departements', 'sections', 'emplois', 'categories',
                'postes', 'salaries', 'criteres', 'profils']
  donnees.value = {}
  for (const c of cles) {
    try { donnees.value[c] = (await api.get('/referentiel/' + c)).data }
    catch { donnees.value[c] = [] }
  }
}
onMounted(charger)

function nomCourt(s) { return s ? s.nom + (s.prenoms ? ' ' + s.prenoms : '') : '' }

function fermer() { forme.value = null; erreur.value = ''; }

function ajouter(t) {
  modeEdition.value = false
  erreur.value = ''
  if (t === 'sites' || t === 'categories' || t === 'postes') forme.value = { t, code: '', libelle: '' }
  else if (t === 'departements') forme.value = { t, code: '', libelle: '', site_id: null }
  else if (t === 'sections') forme.value = { t, code: '', libelle: '', departement_id: null }
  else if (t === 'emplois') forme.value = { t, code: '', libelle: '', famille: 3, profils: [] }
  else if (t === 'criteres') forme.value = { t, code: '', libelle: '', actif: true, details: [] }
  else if (t === 'profils') forme.value = { t, code: '', libelle: '', criteres: [] }
  else if (t === 'salaries') forme.value = { t, matricule: '', nom: '', prenoms: '', site_id: null,
    departement_id: null, section_id: null, emploi_id: null, categorie_id: null, poste_id: null,
    date_embauche: '', email: '', n1_id: null, hors_evaluation: false }
}

function modifier(t, item) {
  ajouter(t)
  modeEdition.value = true
  const f = forme.value
  Object.keys(item).forEach(function (k) { if (k in f && item[k] !== null) f[k] = item[k] })
  if (t === 'emplois') f.profils = (item.profils || []).map(function (p) { return p.id })
  if (t === 'criteres') f.details = (item.details || []).map(function (d) {
    return { libelle_descriptif: d.libelle_descriptif, valeur: d.valeur, ordre: d.ordre } })
  if (t === 'profils') f.criteres = (item.criteres || []).map(function (c) {
    return { critere_id: c.critere_id, coefficient: c.coefficient, ordre: c.ordre } })
  f.id = item.id
}

async function enregistrer() {
  const f = forme.value
  erreur.value = ''
  try {
    if (f.t === 'sites' || f.t === 'categories' || f.t === 'postes') {
      if (modeEdition.value) await api.put('/referentiel/' + f.t + '/' + f.id, { code: f.code, libelle: f.libelle })
      else await api.post('/referentiel/' + f.t, { code: f.code, libelle: f.libelle })
    } else if (f.t === 'departements') {
      const corps = { code: f.code, libelle: f.libelle }
      if (modeEdition.value) await api.put('/referentiel/departements/' + f.id + '?site_id=' + (f.site_id || ''), corps)
      else await api.post('/referentiel/departements?site_id=' + (f.site_id || ''), corps)
    } else if (f.t === 'sections') {
      const corps = { code: f.code, libelle: f.libelle }
      if (modeEdition.value) await api.put('/referentiel/sections/' + f.id + '?departement_id=' + f.departement_id, corps)
      else await api.post('/referentiel/sections?departement_id=' + f.departement_id, corps)
    } else if (f.t === 'emplois') {
      const corps = { code: f.code, libelle: f.libelle }
      if (modeEdition.value) await api.put('/referentiel/emplois/' + f.id + '?famille=' + f.famille, corps)
      else await api.post('/referentiel/emplois?famille=' + f.famille, corps)
      await api.put('/referentiel/emplois/' + f.id + '/profils', { profils: f.profils })
    } else if (f.t === 'criteres') {
      const corps = { code: f.code, libelle: f.libelle, actif: f.actif,
        details: f.details.map(function (d, i) {
          return { libelle_descriptif: d.libelle_descriptif, valeur: Number(d.valeur), ordre: i } }) }
      if (modeEdition.value) await api.put('/referentiel/criteres/' + f.id, corps)
      else await api.post('/referentiel/criteres', corps)
    } else if (f.t === 'profils') {
      const corps = { code: f.code, libelle: f.libelle,
        criteres: f.criteres.map(function (c, i) {
          return { critere_id: c.critere_id, coefficient: Number(c.coefficient), ordre: i } }) }
      if (modeEdition.value) await api.put('/referentiel/profils/' + f.id, corps)
      else await api.post('/referentiel/profils', corps)
    } else if (f.t === 'salaries') {
      const corps = { matricule: f.matricule, nom: f.nom, prenoms: f.prenoms || null,
        site_id: f.site_id || null, departement_id: f.departement_id || null,
        section_id: f.section_id || null, emploi_id: f.emploi_id || null,
        categorie_id: f.categorie_id || null, poste_id: f.poste_id || null,
        date_embauche: f.date_embauche || null, email: f.email || null,
        n1_id: f.n1_id || null, hors_evaluation: !!f.hors_evaluation }
      if (modeEdition.value) await api.put('/referentiel/salaries/' + f.id, corps)
      else await api.post('/referentiel/salaries', corps)
    }
    message.value = 'Enregistré.'
    fermer()
    await charger()
  } catch (e) { erreur.value = (e.response && e.response.data && e.response.data.detail) || 'Erreur.' }
}

async function supprimer(t, item) {
  if (!window.confirm('Supprimer ' + (item.code || item.matricule || item.id) + ' ?')) return
  erreur.value = ''
  try {
    await api.delete('/referentiel/' + t + '/' + item.id)
    message.value = 'Supprimé.'
    await charger()
  } catch (e) { erreur.value = (e.response && e.response.data && e.response.data.detail) || 'Suppression impossible.' }
}

function ajouterDetail() { forme.value.details.push({ libelle_descriptif: '', valeur: 1, ordre: 0 }) }
function ajouterCritereProfil() { forme.value.criteres.push({ critere_id: null, coefficient: 1, ordre: 0 }) }
function monter(liste, i) { if (i > 0) { const x = liste.splice(i, 1)[0]; liste.splice(i - 1, 0, x) } }
function descendre(liste, i) { if (i < liste.length - 1) { const x = liste.splice(i, 1)[0]; liste.splice(i + 1, 0, x) } }

function libelleProfil(id) {
  const p = (donnees.value.profils || []).find(function (x) { return x.id === id })
  return p ? p.libelle : id
}
function libelleCritere(id) {
  const c = (donnees.value.criteres || []).find(function (x) { return x.id === id })
  return c ? c.libelle : id
}
</script>

<template>
  <div>
    <div class="tabs">
      <div v-for="t in ONGLETS" :key="t" class="tab" :class="{ active: onglet === t }"
           @click="onglet = t">{{ t.toUpperCase() }}</div>
    </div>
    <div v-if="message" class="ok">{{ message }}</div>
    <div v-if="erreur && !forme" class="error">{{ erreur }}</div>

    <div class="barre-outils">
      <span class="muted">{{ (donnees[onglet] || []).length }} enregistrement(s)</span>
      <button class="btn" @click="ajouter(onglet)">+ AJOUTER</button>
    </div>

    <table v-if="onglet === 'salaries'" class="data">
      <thead><tr><th>MATRICULE</th><th>NOM</th><th>EMAIL</th><th>N+1</th><th>HORS EVAL</th><th>ACTIONS</th></tr></thead>
      <tbody><tr v-for="s in donnees.salaries" :key="s.id">
        <td>{{ s.matricule }}</td><td>{{ s.nom }} {{ s.prenoms }}</td><td>{{ s.email }}</td>
        <td>{{ s.n1_nom || '—' }}</td><td>{{ s.hors_evaluation ? 'Oui' : 'Non' }}</td>
        <td><button class="btn ghost small" @click="modifier('salaries', s)">Modifier</button>
            <button class="btn danger small" @click="supprimer('salaries', s)">Suppr.</button></td>
      </tr></tbody>
    </table>

    <table v-if="onglet === 'emplois'" class="data">
      <thead><tr><th>CODE</th><th>LIBELLE</th><th>FAMILLE</th><th>PROFILS</th><th>ACTIONS</th></tr></thead>
      <tbody><tr v-for="e in donnees.emplois" :key="e.id">
        <td>{{ e.code }}</td><td>{{ e.libelle }}</td>
        <td>{{ e.famille === 1 ? 'Cadres' : e.famille === 2 ? 'Agents de maîtrise' : 'Employés-Ouvriers' }}</td>
        <td>{{ (e.profils || []).map(p => p.libelle).join(' · ') }}</td>
        <td><button class="btn ghost small" @click="modifier('emplois', e)">Modifier</button>
            <button class="btn danger small" @click="supprimer('emplois', e)">Suppr.</button></td>
      </tr></tbody>
    </table>

    <table v-if="onglet === 'profils'" class="data">
      <thead><tr><th>CODE</th><th>LIBELLE</th><th>CRITERES x COEFF.</th><th>ACTIONS</th></tr></thead>
      <tbody><tr v-for="p in donnees.profils" :key="p.id">
        <td>{{ p.code }}</td><td>{{ p.libelle }}</td>
        <td>{{ (p.criteres || []).map(c => libelleCritere(c.critere_id) + ' x' + c.coefficient).join(' · ') }}</td>
        <td><button class="btn ghost small" @click="modifier('profils', p)">Modifier</button>
            <button class="btn danger small" @click="supprimer('profils', p)">Suppr.</button></td>
      </tr></tbody>
    </table>

    <table v-if="onglet === 'criteres'" class="data">
      <thead><tr><th>CODE</th><th>CRITERE</th><th>DETAILS (libellé → valeur)</th><th>ACTIONS</th></tr></thead>
      <tbody><tr v-for="c in donnees.criteres" :key="c.id">
        <td>{{ c.code }}</td><td>{{ c.libelle }}</td>
        <td><div v-for="d in c.details" :key="d.id">{{ d.libelle_descriptif }} → {{ d.valeur }}</div></td>
        <td><button class="btn ghost small" @click="modifier('criteres', c)">Modifier</button>
            <button class="btn danger small" @click="supprimer('criteres', c)">Suppr.</button></td>
      </tr></tbody>
    </table>

    <template v-for="t in ['sites', 'departements', 'sections', 'categories', 'postes']" :key="t">
      <table v-if="onglet === t" class="data">
        <thead><tr><th>CODE</th><th>LIBELLE</th><th v-if="t === 'departements'">SITE</th><th v-if="t === 'sections'">DEPT</th><th>ACTIONS</th></tr></thead>
        <tbody><tr v-for="r in donnees[t]" :key="r.id">
          <td>{{ r.code }}</td><td>{{ r.libelle }}</td>
          <td v-if="t === 'departements'">{{ (donnees.sites || []).find(s => s.id === r.site_id)?.code || '—' }}</td>
          <td v-if="t === 'sections'">{{ r.departement_id }}</td>
          <td><button class="btn ghost small" @click="modifier(t, r)">Modifier</button>
              <button class="btn danger small" @click="supprimer(t, r)">Suppr.</button></td>
        </tr></tbody>
      </table>
    </template>

    <div v-if="forme" class="modal-bg" @click.self="fermer">
      <div class="modal">
        <h3>{{ modeEdition ? 'MODIFIER' : 'AJOUTER' }} — {{ forme.t.toUpperCase() }}</h3>
        <div v-if="erreur" class="error">{{ erreur }}</div>

        <template v-if="['sites', 'categories', 'postes'].includes(forme.t)">
          <div class="field"><label>CODE</label><input v-model="forme.code" /></div>
          <div class="field"><label>LIBELLE</label><input v-model="forme.libelle" /></div>
        </template>

        <template v-if="forme.t === 'departements'">
          <div class="field"><label>CODE</label><input v-model="forme.code" /></div>
          <div class="field"><label>LIBELLE</label><input v-model="forme.libelle" /></div>
          <div class="field"><label>SITE</label>
            <select v-model="forme.site_id"><option :value="null">—</option>
              <option v-for="s in donnees.sites" :key="s.id" :value="s.id">{{ s.code }} — {{ s.libelle }}</option></select></div>
        </template>

        <template v-if="forme.t === 'sections'">
          <div class="field"><label>CODE</label><input v-model="forme.code" /></div>
          <div class="field"><label>LIBELLE</label><input v-model="forme.libelle" /></div>
          <div class="field"><label>DEPARTEMENT</label>
            <select v-model="forme.departement_id">
              <option v-for="d in donnees.departements" :key="d.id" :value="d.id">{{ d.code }} — {{ d.libelle }}</option></select></div>
        </template>

        <template v-if="forme.t === 'emplois'">
          <div class="field"><label>CODE</label><input v-model="forme.code" /></div>
          <div class="field"><label>LIBELLE</label><input v-model="forme.libelle" /></div>
          <div class="field"><label>FAMILLE</label>
            <select v-model="forme.famille">
              <option :value="1">1 — Cadres</option><option :value="2">2 — Agents de maîtrise</option>
              <option :value="3">3 — Employés-Ouvriers</option></select></div>
          <div class="field"><label>PROFILS ATTRIBUÉS (cocher + ordonner)</label>
            <div v-for="p in donnees.profils" :key="p.id" class="ligne-edit" style="padding-left:2px">
              <input type="checkbox" style="width:auto"
                :checked="forme.profils.includes(p.id)"
                @change="forme.profils.includes(p.id) ? forme.profils.splice(forme.profils.indexOf(p.id), 1) : forme.profils.push(p.id)" />
              <span>{{ p.code }} — {{ p.libelle }}</span>
              <button v-if="forme.profils.includes(p.id)" class="btn ghost small" type="button"
                @click="monter(forme.profils, forme.profils.indexOf(p.id))">↑</button>
              <button v-if="forme.profils.includes(p.id)" class="btn ghost small" type="button"
                @click="descendre(forme.profils, forme.profils.indexOf(p.id))">↓</button>
            </div></div>
        </template>

        <template v-if="forme.t === 'criteres'">
          <div class="field"><label>CODE</label><input v-model="forme.code" /></div>
          <div class="field"><label>CRITERE</label><input v-model="forme.libelle" /></div>
          <div class="field"><label>ACTIF</label><input type="checkbox" v-model="forme.actif" style="width:auto" /></div>
          <label>DETAILS (libellé affiché dans le QCM + valeur cachée /5)</label>
          <div class="lignes-edit">
            <div v-for="(d, i) in forme.details" :key="i" class="ligne-edit">
              <input v-model="d.libelle_descriptif" placeholder="Libellé du détail" />
              <input v-model.number="d.valeur" type="number" step="0.5" style="width:80px" />
              <button class="btn ghost small" type="button" @click="monter(forme.details, i)">↑</button>
              <button class="btn ghost small" type="button" @click="descendre(forme.details, i)">↓</button>
              <button class="btn danger small" type="button" @click="forme.details.splice(i, 1)">✕</button>
            </div>
            <button class="btn ghost small" type="button" @click="ajouterDetail">+ Ajouter un détail</button>
          </div>
        </template>

        <template v-if="forme.t === 'profils'">
          <div class="field"><label>CODE</label><input v-model="forme.code" /></div>
          <div class="field"><label>LIBELLE</label><input v-model="forme.libelle" /></div>
          <label>CRITERES x COEFFICIENT</label>
          <div class="lignes-edit">
            <div v-for="(c, i) in forme.criteres" :key="i" class="ligne-edit">
              <select v-model="c.critere_id">
                <option v-for="cr in donnees.criteres" :key="cr.id" :value="cr.id">{{ cr.code }} — {{ cr.libelle }}</option></select>
              <input v-model.number="c.coefficient" type="number" step="0.5" style="width:80px" />
              <button class="btn ghost small" type="button" @click="monter(forme.criteres, i)">↑</button>
              <button class="btn ghost small" type="button" @click="descendre(forme.criteres, i)">↓</button>
              <button class="btn danger small" type="button" @click="forme.criteres.splice(i, 1)">✕</button>
            </div>
            <button class="btn ghost small" type="button" @click="ajouterCritereProfil">+ Ajouter un critère</button>
          </div>
        </template>

        <template v-if="forme.t === 'salaries'">
          <div class="field"><label>MATRICULE</label><input v-model="forme.matricule" /></div>
          <div class="field"><label>NOM</label><input v-model="forme.nom" /></div>
          <div class="field"><label>PRÉNOMS</label><input v-model="forme.prenoms" /></div>
          <div class="field"><label>SITE</label>
            <select v-model="forme.site_id"><option :value="null">—</option>
              <option v-for="s in donnees.sites" :key="s.id" :value="s.id">{{ s.code }}</option></select></div>
          <div class="field"><label>DÉPARTEMENT</label>
            <select v-model="forme.departement_id"><option :value="null">—</option>
              <option v-for="d in donnees.departements" :key="d.id" :value="d.id">{{ d.code }}</option></select></div>
          <div class="field"><label>SECTION</label>
            <select v-model="forme.section_id"><option :value="null">—</option>
              <option v-for="s in donnees.sections" :key="s.id" :value="s.id">{{ s.code }}</option></select></div>
          <div class="field"><label>EMPLOI</label>
            <select v-model="forme.emploi_id"><option :value="null">—</option>
              <option v-for="e in donnees.emplois" :key="e.id" :value="e.id">{{ e.code }}</option></select></div>
          <div class="field"><label>CATÉGORIE</label>
            <select v-model="forme.categorie_id"><option :value="null">—</option>
              <option v-for="c in donnees.categories" :key="c.id" :value="c.id">{{ c.code }}</option></select></div>
          <div class="field"><label>POSTE</label>
            <select v-model="forme.poste_id"><option :value="null">—</option>
              <option v-for="p in donnees.postes" :key="p.id" :value="p.id">{{ p.code }}</option></select></div>
          <div class="field"><label>DATE EMBAUCHE</label><input v-model="forme.date_embauche" type="date" /></div>
          <div class="field"><label>EMAIL</label><input v-model="forme.email" /></div>
          <div class="field"><label>N+1</label>
            <select v-model="forme.n1_id"><option :value="null">—</option>
              <option v-for="s in donnees.salaries" :key="s.id" :value="s.id">{{ s.matricule }} — {{ nomCourt(s) }}</option></select></div>
          <div class="field"><label>HORS ÉVALUATION</label>
            <input type="checkbox" v-model="forme.hors_evaluation" style="width:auto" /></div>
        </template>

        <div style="display:flex; gap:8px; margin-top:14px">
          <button class="btn" @click="enregistrer">ENREGISTRER</button>
          <button class="btn ghost" @click="fermer">ANNULER</button>
        </div>
      </div>
    </div>
  </div>
</template>
