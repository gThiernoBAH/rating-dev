<!-- 2026-10-03 PATCH UX2 — M6 : hints sur tous les boutons, vraie modale avant
     clôture, rapport de génération conservé. -->
<script setup>
import { onMounted, ref } from 'vue'
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
      <thead><tr><th>NOM</th><th>EXERCICE</th><th>OUVERTURE</th><th>CLÔTURE</th><th>STATUT</th><th>ACTIONS</th></tr></thead>
      <tbody><tr v-for="c in campagnes" :key="c.id">
        <td>{{ c.nom }}</td><td>{{ c.exercice }}</td><td>{{ c.date_ouverture }}</td><td>{{ c.date_cloture }}</td>
        <td>{{ c.statut }}</td>
        <td>
          <button v-if="c.statut === 'Brouillon'" class="btn ghost"
            title="Ouvrir la campagne : elle passe en statut Ouverte"
            @click="ouvrir(c)">OUVRIR</button>
          <span v-if="c.statut === 'Ouverte'" style="margin-left:8px">
            <label style="font-size:11px" title="Générer les fiches des Cadres (famille 1)">
              <input type="checkbox" v-model="familles[1]" /> Cadres</label>
            <label style="font-size:11px" title="Générer les fiches des Agents de maîtrise (famille 2)">
              <input type="checkbox" v-model="familles[2]" /> AM</label>
            <label style="font-size:11px" title="Générer les fiches des Employés-Ouvriers (famille 3)">
              <input type="checkbox" v-model="familles[3]" /> Empl.-Ouvr.</label>
            <button class="btn" title="Générer les fiches d'évaluation des familles cochées (idempotent)"
              @click="action(c, 'generer', { familles: famillesCochees() })">GENERER LES FICHES</button>
            <button class="btn ghost" title="Générer uniquement les fiches manquantes (nouveaux arrivants, rattrapage)"
              @click="action(c, 'generer', { familles: famillesCochees(), rattrapage: true })">RATTRAPAGE</button>
            <button class="btn danger" title="Clôturer définitivement la campagne"
              @click="cloturer(c)">CLOTURER</button>
          </span>
        </td>
      </tr></tbody>
    </table>
  </div>
</template>

<style scoped>
h3 { font-size: 13px; color: var(--color-brand-dark); margin-bottom: 8px; }
.forme { display: flex; gap: 10px; background: var(--color-surface); padding: 14px; border-radius: var(--radius-md); margin-bottom: 12px; flex-wrap: wrap; }
.field { min-width: 160px; }
</style>
