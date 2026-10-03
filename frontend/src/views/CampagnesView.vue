<!-- 2026-10-02 — M6 : liste, création, ouverture, génération automatique par
     famille avec rapport, rattrapage, clôture. Admin seul. -->
<script setup>
import { onMounted, ref } from 'vue'
import api from '../api/client'

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

async function action(c, action, corps) {
  try {
    const rep = await api.post('/campagnes/' + c.id + '/' + action, corps)
    if (action === 'generer') {
      const r = rep.data
      message.value = 'Génération : ' + r.creees + ' créée(s), ' + r.deja_existantes
        + ' déjà existante(s), ' + r.hors_evaluation + ' hors évaluation, '
        + r.cutoff_exclus + ' exclues (cutoff), sans N+1 : '
        + (r.sans_n1.join(', ') || 'aucun')
    } else { message.value = 'Action effectuée : ' + action }
    await charger()
  } catch (e) { erreur.value = e.response?.data?.detail }
}

function famillesCochees() { return Object.keys(familles.value).filter(k => familles.value[k]).map(Number) }
</script>

<template>
  <div>
    <h3>CRÉER UNE CAMPAGNE</h3>
    <div class="forme">
      <div class="field"><label>NOM</label><input v-model="forme.nom" /></div>
      <div class="field"><label>EXERCICE</label><input type="number" v-model="forme.exercice" /></div>
      <div class="field"><label>OUVERTURE</label><input type="date" v-model="forme.date_ouverture" /></div>
      <div class="field"><label>CLÔTURE</label><input type="date" v-model="forme.date_cloture" /></div>
      <button class="btn" @click="creer">CREER</button>
    </div>
    <div v-if="message" class="ok">{{ message }}</div>
    <div v-if="erreur" class="error">{{ erreur }}</div>

    <table class="data">
      <thead><tr><th>NOM</th><th>EXERCICE</th><th>OUVERTURE</th><th>CLÔTURE</th><th>STATUT</th><th>ACTIONS</th></tr></thead>
      <tbody><tr v-for="c in campagnes" :key="c.id">
        <td>{{ c.nom }}</td><td>{{ c.exercice }}</td><td>{{ c.date_ouverture }}</td><td>{{ c.date_cloture }}</td>
        <td>{{ c.statut }}</td>
        <td>
          <button v-if="c.statut === 'Brouillon'" class="btn ghost" @click="action(c, 'ouvrir', {})">OUVRIR</button>
          <span v-if="c.statut === 'Ouverte'" style="margin-left:8px">
            <label style="font-size:11px"><input type="checkbox" v-model="familles[1]" /> Cadres</label>
            <label style="font-size:11px"><input type="checkbox" v-model="familles[2]" /> AM</label>
            <label style="font-size:11px"><input type="checkbox" v-model="familles[3]" /> Empl.-Ouvr.</label>
            <button class="btn" @click="action(c, 'generer', { familles: famillesCochees() })">GENERER LES FICHES</button>
            <button class="btn ghost" @click="action(c, 'generer', { familles: famillesCochees(), rattrapage: true })">RATTRAPAGE</button>
            <button class="btn danger" @click="action(c, 'cloturer', {})">CLOTURER</button>
          </span>
        </td>
      </tr></tbody>
    </table>
  </div>
</template>

<style scoped>
h3 { font-size: 13px; color: #0f3b66; margin-bottom: 8px; }
.forme { display: flex; gap: 10px; background: #fff; padding: 14px; border-radius: 6px; margin-bottom: 12px; flex-wrap: wrap; }
.field { min-width: 160px; }
</style>
