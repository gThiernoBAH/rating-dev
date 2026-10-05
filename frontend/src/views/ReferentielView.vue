<!-- 2026-10-03 PATCH UX2 — M5 : DataTable (recherche/tri/pagination) sur les
     9 onglets, colonne Actions en icônes avec hints, suppression via vraie
     modale (plus de window.confirm), onglets soulignés façon vusine. -->
<script setup>
import { onMounted, ref, computed } from 'vue'
import { Pencil, Trash2, Plus, KeyRound } from 'lucide-vue-next'
import api from '../api/client'
import DataTable from '../components/DataTable.vue'
import { useConfirm } from '../composables/useConfirm'

const { confirm } = useConfirm()
const onglet = ref('salaries')
const donnees = ref({})
const message = ref('')
const erreur = ref('')
const forme = ref(null)
const modeEdition = ref(false)

const ONGLETS = ['sites', 'departements', 'sections', 'emplois', 'categories',   // PATCH 12 : ordre demandé
                 'postes', 'salaries', 'details_criteres', 'criteres', 'profils']
const LIBELLES = {   // PATCH 12
  sites: 'Sites', departements: 'Départements', sections: 'Sections',
  emplois: 'Emplois', categories: 'Catégories', postes: 'Postes',
  salaries: 'Salariés', details_criteres: 'Détails Critères',
  criteres: 'Critères', profils: 'Profils',
}

async function charger() {
  const cles = ['sites', 'departements', 'sections', 'emplois', 'categories',
                'postes', 'salaries', 'criteres', 'profils']
  donnees.value = {}
  for (const c of cles) {
    try { donnees.value[c] = (await api.get('/referentiel/' + (c === 'details_criteres' ? 'details-criteres' : c))).data }  // PATCH 12
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
  else if (t === 'details_criteres') forme.value = { t, libelle_descriptif: '', valeur: 1, sens: 1, valeur_min: null, valeur_max: null, actif: true }   // PATCH 12
  else if (t === 'criteres') forme.value = { t, code: '', libelle: '', actif: true, editable: false, details: [] }   // PATCH 12
  else if (t === 'profils') forme.value = { t, code: '', libelle: '', criteres: [] }
  else if (t === 'salaries') forme.value = { t, matricule: '', nom: '', prenoms: '', site_id: null,
    departement_id: null, section_id: null, emploi_id: null, categorie_id: null, poste_id: null,
    date_embauche: '', email: '', n1_id: null, n2_id: null, hors_evaluation: false,
    nature: 'Embauché', is_admin: false, is_active: true }   // PATCH 12 : nature
}

function modifier(t, item) {
  ajouter(t)
  modeEdition.value = true
  const f = forme.value
  Object.keys(item).forEach(function (k) { if (k in f && item[k] !== null) f[k] = item[k] })
  if (t === 'emplois') f.profils = (item.profils || []).map(function (p) { return p.id })
  if (t === 'criteres') f.details = (item.details || []).map(function (d) {   // PATCH 12
    return { libelle_descriptif: d.libelle_descriptif, valeur: d.valeur, ordre: d.ordre,
             sens: d.sens || 1, valeur_min: d.valeur_min, valeur_max: d.valeur_max, actif: d.actif !== false } })
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
    } else if (f.t === 'details_criteres') {   // PATCH 12
      const corps = { libelle_descriptif: f.libelle_descriptif, valeur: Number(f.valeur), ordre: 0,
        sens: Number(f.sens || 1),
        valeur_min: Number(f.sens) === 2 && f.valeur_min !== null ? Number(f.valeur_min) : null,
        valeur_max: Number(f.sens) === 2 && f.valeur_max !== null ? Number(f.valeur_max) : null,
        actif: !!f.actif }
      if (modeEdition.value) await api.put('/referentiel/details-criteres/' + f.id, corps)
      else await api.post('/referentiel/details-criteres', corps)
    } else if (f.t === 'criteres') {
      const corps = { code: f.code, libelle: f.libelle, actif: f.actif, editable: !!f.editable,   // PATCH 12
        details: f.details.map(function (d, i) {
          return { libelle_descriptif: d.libelle_descriptif, valeur: Number(d.valeur), ordre: i,
            sens: Number(d.sens || 1),
            valeur_min: Number(d.sens) === 2 && d.valeur_min != null ? Number(d.valeur_min) : null,
            valeur_max: Number(d.sens) === 2 && d.valeur_max != null ? Number(d.valeur_max) : null,
            actif: d.actif !== false } }) }
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
        n1_id: f.n1_id || null, n2_id: f.n2_id || null,
        hors_evaluation: !!f.hors_evaluation,
        is_admin: !!f.is_admin, is_active: f.is_active !== false,
        nature: f.nature || 'Embauché' }   // PATCH 12
      if (modeEdition.value) await api.put('/referentiel/salaries/' + f.id, corps)
      else await api.post('/referentiel/salaries', corps)
    }
    message.value = 'Enregistré.'
    fermer()
    await charger()
  } catch (e) { erreur.value = (e.response && e.response.data && e.response.data.detail) || 'Erreur.' }
}

async function supprimer(t, item) {
  const nom = item.code || item.matricule || item.id
  const ok = await confirm({
    title: 'Supprimer — ' + LIBELLES[t],
    message: `Supprimer « ${nom} » ? Cette action est définitive.`,
    danger: true, confirmLabel: 'Supprimer',
  })
  if (!ok) return
  erreur.value = ''
  try {
    await api.delete('/referentiel/' + (t === 'details_criteres' ? 'details-criteres' : t) + '/' + item.id)   // PATCH 12
    message.value = 'Supprimé.'
    await charger()
  } catch (e) { erreur.value = (e.response && e.response.data && e.response.data.detail) || 'Suppression impossible.' }
}

async function reinitialiserMdp(s) {
  const ok = await confirm({
    title: 'Réinitialiser le mot de passe',
    message: `Vider le mot de passe de ${s.matricule} — ${nomCourt(s)} ? À sa prochaine connexion, il devra en créer un nouveau.`,
    danger: true, confirmLabel: 'Réinitialiser',
  })
  if (!ok) return
  try {
    await api.post('/referentiel/salaries/' + s.id + '/reset-password')
    message.value = 'Mot de passe réinitialisé.'
    await charger()
  } catch (e) { erreur.value = e.response?.data?.detail || 'Action impossible.' }
}

async function reinitialiserTous() {
  const ok = await confirm({
    title: 'Réinitialiser TOUS les mots de passe',
    message: 'Vider le mot de passe de tous les salariés (sauf Admins) ? Chacun devra créer le sien à sa prochaine connexion.',
    danger: true, confirmLabel: 'Tout réinitialiser',
  })
  if (!ok) return
  try {
    const r = await api.post('/referentiel/salaries/reset-passwords')
    message.value = r.data.detail
    await charger()
  } catch (e) { erreur.value = e.response?.data?.detail || 'Action impossible.' }
}

function ajouterDetail() { forme.value.details.push({ libelle_descriptif: '', valeur: 1, ordre: 0,
  sens: 1, valeur_min: null, valeur_max: null, actif: true }) }   // PATCH 12
function ajouterDetailBiblio(ev) {   // PATCH 12 : depuis la bibliothèque Détails Critères
  const b = (donnees.value.details_criteres || []).find(d => d.id === Number(ev.target.value))
  if (b) forme.value.details.push({ libelle_descriptif: b.libelle_descriptif, valeur: b.valeur,
    ordre: forme.value.details.length, sens: b.sens || 1, valeur_min: b.valeur_min,
    valeur_max: b.valeur_max, actif: b.actif !== false })
  ev.target.value = ''
}
function nbSalaries(r) {   // PATCH 12 : comptage des salariés rattachés
  const cle = ({ sites: 'site_id', departements: 'departement_id', sections: 'section_id',
    emplois: 'emploi_id', categories: 'categorie_id', postes: 'poste_id' })[onglet.value]
  if (!cle) return 0
  return (donnees.value.salaries || []).filter(s => s[cle] === r.id).length
}
async function basculerActif(t, row) {   // PATCH 12
  erreur.value = ''
  try {
    await api.patch('/referentiel/' + t + '/' + row.id + '/toggle-active')
    message.value = (row.actif === false ? 'Réactivé' : 'Désactivé') + ' : ' + (row.code || '')
    await charger()
  } catch (e) { erreur.value = e.response?.data?.detail || 'Action impossible.' }
}
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
function libelleDepartement(id) {
  const d = (donnees.value.departements || []).find(function (x) { return x.id === id })
  return d ? d.libelle : id
}

/* --- Colonnes du DataTable par onglet --- */
const FAMILLES = { 1: 'Cadres', 2: 'Agents de maîtrise', 3: 'Employés-Ouvriers' }
const ACTIONS = { key: 'actions', label: 'Actions', sortable: false, searchable: false, align: 'center' }

const colonnes = computed(() => {
  const t = onglet.value
  if (t === 'salaries') return [
    { key: 'matricule', label: 'Matricule' },
    { key: 'nom', label: 'Nom', format: (v, r) => nomCourt(r) },
    { key: 'n1_nom', label: 'N+1' },
    { key: 'n2_nom', label: 'N+2' },
    { key: 'nature', label: 'Nature' },   // PATCH 12
    { key: 'hors_evaluation', label: 'Hors éval.', format: v => (v ? 'Oui' : 'Non'), align: 'center' },
    { key: 'actif_aff', label: 'Actif', format: v => v, align: 'center', searchable: false },
    ACTIONS,
  ]
  if (t === 'emplois') return [
    { key: 'code', label: 'Code' },
    { key: 'libelle', label: 'Libellé' },
    { key: 'famille', label: 'Famille', format: v => FAMILLES[v] || v },
    { key: 'profils_liste', label: 'Profils', keyFn: r => r },
    { key: 'nb_salaries', label: 'Nb Salariés', align: 'center', searchable: false },   // PATCH 12 (emplois)
    { key: 'actif_aff', label: 'Actif', format: v => v, align: 'center', searchable: false },
    ACTIONS,
  ]
  if (t === 'profils') return [
    { key: 'code', label: 'Code' },
    { key: 'libelle', label: 'Libellé' },
    { key: 'criteres_liste', label: 'Critères × coeff.' },
    ACTIONS,
  ]
  if (t === 'criteres') return [
    { key: 'code', label: 'Code' },
    { key: 'libelle', label: 'Critère' },
    { key: 'details_liste', label: 'Détails (libellé → valeur)' },
    ACTIONS,
  ]
  if (t === 'departements') return [
    { key: 'code', label: 'Code' },
    { key: 'libelle', label: 'Libellé' },
    { key: 'site_code', label: 'Site' },
    { key: 'nb_salaries', label: 'Nb Salariés', align: 'center', searchable: false },   // PATCH 12 (départements)
    { key: 'actif_aff', label: 'Actif', format: v => v, align: 'center', searchable: false },
    ACTIONS,
  ]
  if (t === 'sections') return [
    { key: 'code', label: 'Code' },
    { key: 'libelle', label: 'Libellé' },
    { key: 'dept_libelle', label: 'Département' },
    { key: 'nb_salaries', label: 'Nb Salariés', align: 'center', searchable: false },   // PATCH 12 (sections)
    { key: 'actif_aff', label: 'Actif', format: v => v, align: 'center', searchable: false },
    ACTIONS,
  ]
  if (t === 'details_criteres') return [   // PATCH 12
    { key: 'libelle_descriptif', label: 'Descriptif' },
    { key: 'type_aff', label: 'Type valeur' },
    { key: 'val_aff', label: 'Valeur' },
    { key: 'actif_aff', label: 'Actif', format: v => v, align: 'center', searchable: false },
    ACTIONS,
  ]
  return [
    { key: 'code', label: 'Code' },
    { key: 'libelle', label: 'Libellé' },
    { key: 'nb_salaries', label: 'Nb Salariés', align: 'center', searchable: false },   // PATCH 12 (défaut)
    { key: 'actif_aff', label: 'Actif', format: v => v, align: 'center', searchable: false },
    ACTIONS,
  ]
})

/* lignes enrichies pour le DataTable */
const lignes = computed(() => {
  const t = onglet.value
  const base = donnees.value[t] || []
  if (t === 'salaries') return base.map(s => ({
    ...s, actif_aff: s.is_active ? 'Actif' : 'Inactif',
    admin_tri: s.is_admin ? 0 : 1,   // PATCH 12 : Admins en tête
  }))
  if (t === 'emplois') return base.map(e => ({
    ...e,
    profils_liste: (e.profils || []).map(p => p.libelle).join(' · '),
    nb_salaries: nbSalaries(e), actif_aff: e.actif !== false ? 'Actif' : 'Inactif',   // PATCH 12
  }))
  if (t === 'profils') return base.map(p => ({
    ...p,
    criteres_liste: (p.criteres || []).map(c => libelleCritere(c.critere_id) + ' ×' + c.coefficient).join(' · '),
  }))
  if (t === 'criteres') return base.map(c => ({ ...c, details_liste: ' ' }))
  if (t === 'details_criteres') return base.map(d => ({   // PATCH 12
    ...d,
    type_aff: Number(d.sens) === 2 ? 'Intervalle' : 'Unique',
    val_aff: Number(d.sens) === 2 ? (d.valeur_min + ' à ' + d.valeur_max) : d.valeur,
    actif_aff: d.actif !== false ? 'Actif' : 'Inactif',
  }))
  if (t === 'departements') return base.map(d => ({
    ...d,
    site_code: (donnees.value.sites || []).find(s => s.id === d.site_id)?.code || '—',
    nb_salaries: nbSalaries(d), actif_aff: d.actif !== false ? 'Actif' : 'Inactif',   // PATCH 12
  }))
  if (t === 'sections') return base.map(s => ({
    ...s,
    dept_libelle: libelleDepartement(s.departement_id),
    nb_salaries: nbSalaries(s), actif_aff: s.actif !== false ? 'Actif' : 'Inactif',   // PATCH 12
  }))
  return base.map(r => ({ ...r, nb_salaries: nbSalaries(r),   // PATCH 12
    actif_aff: r.actif !== false ? 'Actif' : 'Inactif' }))
})
function cleLigne(r, i) { return r.id ?? i }
</script>

<template>
  <div>
    <div class="tabs">
      <button v-for="t in ONGLETS" :key="t" class="tab" :class="{ active: onglet === t }"
        :title="'Onglet ' + LIBELLES[t]" @click="onglet = t">{{ LIBELLES[t] }}</button>
    </div>
    <div v-if="message" class="ok">{{ message }}</div>
    <div v-if="erreur && !forme" class="error">{{ erreur }}</div>

    <DataTable :columns="colonnes" :rows="lignes" :row-key="cleLigne"
      :default-sort="onglet === 'salaries' ? { key: 'admin_tri', dir: 1 } : null"
      :search-placeholder="`Rechercher un ${LIBELLES[onglet].toLowerCase().replace(/s$/, '')}…`">
      <template #filtres>
        <button class="btn" title="Ajouter un nouvel enregistrement dans cet onglet"
          @click="ajouter(onglet)"><Plus :size="14" /> AJOUTER</button>
        <button v-if="onglet === 'salaries'" class="btn ghost" style="margin-left:6px"
          title="Vider tous les mots de passe (sauf Admins) : chacun créera le sien à sa prochaine connexion"
          @click="reinitialiserTous"><KeyRound :size="14" /> RÉINIT. TOUS LES MDP</button>
      </template>

      <!-- colonnes spéciales -->
      <template #cell-details_liste="{ row }">
        <div v-for="d in row.details" :key="d.id">{{ d.libelle_descriptif }} → {{ d.valeur }}</div>
      </template>
      <template #cell-actif_aff="{ row }">
        <span v-if="onglet === 'salaries'" class="badge-statut" :class="row.is_active ? 'statut-vert' : 'statut-rouge'">
          {{ row.is_active ? 'Actif' : 'Inactif' }}
        </span>
        <button v-else class="badge-statut" :class="row.actif !== false ? 'statut-vert' : 'statut-rouge'"
          :title="row.actif !== false ? 'Désactiver ce référentiel : plus pris en compte à la génération des fiches' : 'Réactiver ce référentiel'"
          @click="basculerActif(onglet, row)">{{ row.actif !== false ? 'Actif' : 'Inactif' }}</button>
      </template>
      <template #cell-actions="{ row }">
        <button v-if="onglet === 'salaries'" class="icon-btn"
          :title="'Réinitialiser le mot de passe de ' + row.matricule + ' (il en créera un nouveau à sa prochaine connexion)'"
          @click="reinitialiserMdp(row)"><KeyRound :size="15" /></button>
        <button class="icon-btn" style="margin-left:6px"
          :title="'Modifier — ' + (row.code || row.matricule || row.id)"
          @click="modifier(onglet, row)"><Pencil :size="15" /></button>
        <button class="icon-btn danger" style="margin-left:6px"
          :title="'Supprimer — ' + (row.code || row.matricule || row.id)"
          @click="supprimer(onglet, row)"><Trash2 :size="15" /></button>
      </template>
    </DataTable>

    <div v-if="forme" class="modal-bg" @click.self="fermer">
      <div class="modal">
        <h3>{{ modeEdition ? 'MODIFIER' : 'AJOUTER' }} — {{ forme.t.toUpperCase() }}</h3>
        <div v-if="erreur" class="error">{{ erreur }}</div>

        <template v-if="['sites', 'categories', 'postes'].includes(forme.t)">
          <div class="field"><label>CODE</label><input v-model="forme.code" title="Code unique (ex. DUPL)" /></div>
          <div class="field"><label>LIBELLE</label><input v-model="forme.libelle" title="Libellé complet" /></div>
        </template>

        <template v-if="forme.t === 'departements'">
          <div class="field"><label>CODE</label><input v-model="forme.code" title="Code unique du département" /></div>
          <div class="field"><label>LIBELLE</label><input v-model="forme.libelle" title="Libellé complet" /></div>
          <div class="field"><label>SITE</label>
            <select v-model="forme.site_id" title="Site de rattachement du département">
              <option :value="null">—</option>
              <option v-for="s in donnees.sites" :key="s.id" :value="s.id">{{ s.code }} — {{ s.libelle }}</option></select></div>
        </template>

        <template v-if="forme.t === 'sections'">
          <div class="field"><label>CODE</label><input v-model="forme.code" title="Code unique de la section" /></div>
          <div class="field"><label>LIBELLE</label><input v-model="forme.libelle" title="Libellé complet" /></div>
          <div class="field"><label>DEPARTEMENT</label>
            <select v-model="forme.departement_id" title="Département de rattachement de la section">
              <option v-for="d in donnees.departements" :key="d.id" :value="d.id">{{ d.code }} — {{ d.libelle }}</option></select></div>
        </template>

        <template v-if="forme.t === 'emplois'">
          <div class="field"><label>CODE</label><input v-model="forme.code" title="Code emploi (CD, CM, CS, AM, EN, EQ, ON, OQ…)" /></div>
          <div class="field"><label>LIBELLE</label><input v-model="forme.libelle" title="Libellé complet de l'emploi" /></div>
          <div class="field"><label>FAMILLE</label>
            <select v-model="forme.famille" title="Famille d'emploi : détermine la grille de génération des fiches">
              <option :value="1">1 — Cadres</option><option :value="2">2 — Agents de maîtrise</option>
              <option :value="3">3 — Employés-Ouvriers</option></select></div>
          <div class="field"><label>PROFILS ATTRIBUÉS (cocher + ordonner)</label>
            <div v-for="p in donnees.profils" :key="p.id" class="ligne-edit" style="padding-left:2px">
              <input type="checkbox" style="width:auto" title="Attribuer ce profil à l'emploi"
                :checked="forme.profils.includes(p.id)"
                @change="forme.profils.includes(p.id) ? forme.profils.splice(forme.profils.indexOf(p.id), 1) : forme.profils.push(p.id)" />
              <span>{{ p.code }} — {{ p.libelle }}</span>
              <button v-if="forme.profils.includes(p.id)" class="btn ghost small" type="button"
                title="Monter ce profil d'un cran (ordre des onglets de la fiche)"
                @click="monter(forme.profils, forme.profils.indexOf(p.id))">↑</button>
              <button v-if="forme.profils.includes(p.id)" class="btn ghost small" type="button"
                title="Descendre ce profil d'un cran"
                @click="descendre(forme.profils, forme.profils.indexOf(p.id))">↓</button>
            </div></div>
        </template>

        <template v-if="forme.t === 'criteres'">
          <div class="field"><label>CODE</label><input v-model="forme.code" title="Code unique du critère" /></div>
          <div class="field"><label>CRITERE</label><input v-model="forme.libelle" title="Libellé du critère affiché dans la grille" /></div>
          <div class="field"><label>ACTIF</label><input type="checkbox" v-model="forme.actif" style="width:auto" title="Critère actif (utilisable dans les profils)" /></div>
          <div class="field"><label>EDITABLE (« A REMPLIR »)</label>   <!-- PATCH 12 -->
            <input type="checkbox" v-model="forme.editable" style="width:auto"
              title="Critère éditable : le libellé est pré-rempli avec les objectifs de la campagne précédente, le salarié peut l'ajuster à l'auto-évaluation" /></div>
          <label>DETAILS (libellé affiché dans le QCM + valeur cachée /5)</label>
          <div class="lignes-edit">
            <div v-for="(d, i) in forme.details" :key="i" class="ligne-edit">
              <input v-model="d.libelle_descriptif" placeholder="Libellé du détail" style="flex:1"
                 title="Texte proposé à la case dans le QCM" />
              <select v-model.number="d.sens" style="width:104px"
                title="Type de valeur : unique (un chiffre) ou intervalle (min-max, ajustable par étoiles)">
                <option :value="1">Unique</option><option :value="2">Intervalle</option></select>
              <template v-if="Number(d.sens) === 2">
                <input v-model.number="d.valeur_min" type="number" step="0.5" style="width:60px" title="Borne minimale" placeholder="min" />
                <input v-model.number="d.valeur_max" type="number" step="0.5" style="width:60px" title="Borne maximale" placeholder="max" />
              </template>
              <input v-else v-model.number="d.valeur" type="number" step="0.5" style="width:60px" title="Valeur cachée du détail (contribute au score /5)" />
              <button class="btn ghost small" type="button" title="Monter ce détail" @click="monter(forme.details, i)">↑</button>
              <button class="btn ghost small" type="button" title="Descendre ce détail" @click="descendre(forme.details, i)">↓</button>
              <button class="btn danger small" type="button" title="Retirer ce détail du critère" @click="forme.details.splice(i, 1)">✕</button>
            </div>
            <button class="btn ghost small" type="button" title="Ajouter une ligne de détail au QCM" @click="ajouterDetail">+ Ajouter un détail</button>
            <select v-if="(donnees.details_criteres || []).some(x => !x.critere_id)"
              style="margin-top:6px" title="Ajouter un détail existant depuis la bibliothèque Détails Critères"
              @change="ajouterDetailBiblio">
              <option value="">+ Depuis la bibliothèque…</option>
              <option v-for="b in (donnees.details_criteres || []).filter(x => !x.critere_id)" :key="b.id" :value="b.id">{{ b.libelle_descriptif }}</option>
            </select>
          </div>
        </template>

        <template v-if="forme.t === 'details_criteres'">   <!-- PATCH 12 -->
          <div class="field"><label>DESCRIPTIF</label><input v-model="forme.libelle_descriptif" title="Libellé du détail proposé dans les QCM" /></div>
          <div class="field"><label>TYPE VALEUR</label>
            <select v-model.number="forme.sens" title="Valeur unique (un chiffre) ou valeur à intervalle (min-max, ajustable par étoiles)">
              <option :value="1">Valeur unique</option><option :value="2">Valeur à intervalle</option></select></div>
          <div class="field" v-if="Number(forme.sens) === 2"><label>MIN / MAX</label>
            <div style="display:flex;gap:8px">
              <input v-model.number="forme.valeur_min" type="number" step="0.5" title="Borne minimale de l'intervalle" />
              <input v-model.number="forme.valeur_max" type="number" step="0.5" title="Borne maximale de l'intervalle" /></div></div>
          <div class="field" v-else><label>VALEUR</label><input v-model.number="forme.valeur" type="number" step="0.5" title="Valeur cachée du détail" /></div>
          <div class="field"><label>ACTIF</label><input type="checkbox" v-model="forme.actif" style="width:auto" title="Détail actif (proposé dans les QCM)" /></div>
        </template>

        <template v-if="forme.t === 'profils'">
          <div class="field"><label>CODE</label><input v-model="forme.code" title="Code unique du profil" /></div>
          <div class="field"><label>LIBELLE</label><input v-model="forme.libelle" title="Libellé du profil (titre de l'onglet dans la fiche)" /></div>
          <label>CRITERES x COEFFICIENT</label>
          <div class="lignes-edit">
            <div v-for="(c, i) in forme.criteres" :key="i" class="ligne-edit">
              <select v-model="c.critere_id" title="Critère évalué dans ce profil">
                <option v-for="cr in donnees.criteres" :key="cr.id" :value="cr.id">{{ cr.code }} — {{ cr.libelle }}</option></select>
              <input v-model.number="c.coefficient" type="number" step="0.5" style="width:80px" title="Coefficient de pondération du critère dans le profil" />
              <button class="btn ghost small" type="button" title="Monter ce critère" @click="monter(forme.criteres, i)">↑</button>
              <button class="btn ghost small" type="button" title="Descendre ce critère" @click="descendre(forme.criteres, i)">↓</button>
              <button class="btn danger small" type="button" title="Retirer ce critère du profil" @click="forme.criteres.splice(i, 1)">✕</button>
            </div>
            <button class="btn ghost small" type="button" title="Ajouter un critère pondéré au profil" @click="ajouterCritereProfil">+ Ajouter un critère</button>
          </div>
        </template>

        <template v-if="forme.t === 'salaries'">
          <div class="field"><label>MATRICULE</label><input v-model="forme.matricule" title="Matricule = identifiant de connexion du salarié" /></div>
          <div class="field"><label>NOM</label><input v-model="forme.nom" title="Nom du salarié" /></div>
          <div class="field"><label>PRÉNOMS</label><input v-model="forme.prenoms" title="Prénoms du salarié" /></div>
          <div class="field"><label>NATURE</label>   <!-- PATCH 12 -->
            <select v-model="forme.nature" title="Nature du contrat : Embauché, Journalier, Contractuel, Stagiaire ou Apprenti">
              <option>Embauché</option><option>Journalier</option><option>Contractuel</option>
              <option>Stagiaire</option><option>Apprenti</option></select></div>
          <div class="field"><label>SITE</label>
            <select v-model="forme.site_id" title="Site d'affectation"><option :value="null">—</option>
              <option v-for="s" in donnees.sites" :key="s.id" :value="s.id">{{ s.code }} — {{ s.libelle }}</option>   <!-- PATCH 12 --></select></div>
          <div class="field"><label>DÉPARTEMENT</label>
            <select v-model="forme.departement_id" title="Département d'affectation"><option :value="null">—</option>
              <option v-for="d" in donnees.departements" :key="d.id" :value="d.id">{{ d.code }} — {{ d.libelle }}</option>   <!-- PATCH 12 --></select></div>
          <div class="field"><label>SECTION</label>
            <select v-model="forme.section_id" title="Section d'affectation"><option :value="null">—</option>
              <option v-for="s" in donnees.sections" :key="s.id" :value="s.id">{{ s.code }} — {{ s.libelle }}</option>   <!-- PATCH 12 --></select></div>
          <div class="field"><label>EMPLOI</label>
            <select v-model="forme.emploi_id" title="Emploi : détermine les profils d'évaluation de la fiche"><option :value="null">—</option>
              <option v-for="e" in donnees.emplois" :key="e.id" :value="e.id">{{ e.code }} — {{ e.libelle }}</option>   <!-- PATCH 12 --></select></div>
          <div class="field"><label>CATÉGORIE</label>
            <select v-model="forme.categorie_id" title="Catégorie du salarié"><option :value="null">—</option>
              <option v-for="c" in donnees.categories" :key="c.id" :value="c.id">{{ c.code }} — {{ c.libelle }}</option>   <!-- PATCH 12 --></select></div>
          <div class="field"><label>POSTE</label>
            <select v-model="forme.poste_id" title="Poste occupé"><option :value="null">—</option>
              <option v-for="p" in donnees.postes" :key="p.id" :value="p.id">{{ p.code }} — {{ p.libelle }}</option>   <!-- PATCH 12 --></select></div>
          <div class="field"><label>DATE EMBAUCHE</label><input v-model="forme.date_embauche" type="date" title="Date d'embauche (servira au cutoff d'ancienneté)" /></div>
          <div class="field"><label>EMAIL</label><input v-model="forme.email" title="Adresse email professionnelle (notifications)" /></div>
          <div class="field"><label>N+1</label>
            <select v-model="forme.n1_id" title="Responsable direct (N+1) : évaluera la fiche après l'auto-évaluation"><option :value="null">—</option>
              <option v-for="s in donnees.salaries" :key="s.id" :value="s.id">{{ s.matricule }} — {{ nomCourt(s) }}</option></select></div>
          <div class="field"><label>N+2</label>
            <select v-model="forme.n2_id" title="N+2 explicite : approuvera la fiche après l'évaluation N+1 (sinon déduit du N+1 du N+1)"><option :value="null">—</option>
              <option v-for="s in donnees.salaries" :key="s.id" :value="s.id">{{ s.matricule }} — {{ nomCourt(s) }}</option></select></div>
          <div class="field"><label>HORS ÉVALUATION</label>
            <input type="checkbox" v-model="forme.hors_evaluation" style="width:auto" title="Exclure ce salarié de la génération des fiches" /></div>
          <div class="field"><label>ADMINISTRATEUR</label>
            <input type="checkbox" v-model="forme.is_admin" style="width:auto"
              title="Compte Administrateur : accès au paramétrage, campagnes et tableaux de bord. Exclu des évaluations et statistiques." /></div>
          <div class="field"><label>ACTIF</label>
            <input type="checkbox" v-model="forme.is_active" style="width:auto"
              title="Compte actif : le salarié peut se connecter. Décoché : connexion refusée (fiches existantes conservées)." /></div>
        </template>

        <div style="display:flex; gap:8px; margin-top:14px; justify-content:flex-end">
          <button class="btn ghost" title="Annuler sans enregistrer" @click="fermer">ANNULER</button>
          <button class="btn" title="Enregistrer et fermer" @click="enregistrer">ENREGISTRER</button>
        </div>
      </div>
    </div>
  </div>
</template>
