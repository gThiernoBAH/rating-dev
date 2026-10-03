<!-- 2026-10-02 — M3bis : GRAPHE (salarié bleu vs section orange) / RECAP
     + benchmark inter-sections + historique inter-exercices. Consultation seule. -->
<script setup>
import { onMounted, ref } from 'vue'
import api from '../api/client'

const salaries = ref([])
const campagneId = ref('')
const salarieId = ref('')
const graphe = ref([])
const recap = ref([])
const mode = ref('GRAPHE')
const benchmarkCritere = ref('')
const benchmark = ref([])
const historique = ref([])
const criteres = ref([])

onMounted(async () => {
  salaries.value = (await api.get('/navigation/salaries')).data
  criteres.value = (await api.get('/referentiel/criteres')).data
  try {
    const { data } = await api.get('/espace')
    campagneId.value = data.campagnes_actives[0]?.id || ''
  } catch { /* Admin sans campagne */ }
})

async function afficher() {
  if (!salarieId.value || !campagneId.value) return
  const params = { salarie_id: salarieId.value, campagne_id: campagneId.value }
  graphe.value = (await api.get('/navigation/graphe', { params })).data
  recap.value = (await api.get('/navigation/recap', { params })).data
  historique.value = (await api.get('/navigation/historique', { params: { salarie_id: salarieId.value } })).data
}

async function lancerBenchmark() {
  if (!benchmarkCritere.value || !campagneId.value) return
  benchmark.value = (await api.get('/navigation/benchmark', {
    params: { critere_id: benchmarkCritere.value, campagne_id: campagneId.value }
  })).data
}
</script>

<template>
  <div>
    <div class="barre">
      <select v-model="salarieId" @change="afficher">
        <option value="">— Choisir un salarié —</option>
        <option v-for="s in salaries" :key="s.id" :value="s.id">{{ s.matricule }} – {{ s.nom }}</option>
      </select>
      <div class="tabs" style="margin:0">
        <div class="tab" :class="{ active: mode === 'GRAPHE' }" @click="mode = 'GRAPHE'">GRAPHE</div>
        <div class="tab" :class="{ active: mode === 'RECAP' }" @click="mode = 'RECAP'">RECAP</div>
      </div>
    </div>

    <h4 v-if="mode === 'GRAPHE'">REPRÉSENTATION ÉVALUATION DU SALARIÉ PAR RAPPORT À SA SECTION</h4>
    <div v-if="mode === 'GRAPHE'" class="graphe">
      <div v-for="g in graphe" :key="g.critere" class="barre-critere">
        <div class="crit-label">{{ g.critere }}</div>
        <div class="tracks">
          <div class="track"><div class="fill salarie" :style="{ width: (g.salarie / 5 * 100) + '%' }"></div></div>
          <div class="track"><div class="fill section" :style="{ width: (g.section / 5 * 100) + '%' }"></div></div>
        </div>
        <span class="vals">{{ g.salarie }} / {{ g.section }}</span>
      </div>
      <p class="muted"><span class="legende salarie">&nbsp;</span> Salarié &nbsp; <span class="legende section">&nbsp;</span> Section</p>
    </div>

    <h4 v-if="mode === 'RECAP'">RÉCAPITULATIF DES NOTES D'ÉVALUATION DU SALARIÉ PAR RAPPORT À SA SECTION</h4>
    <table v-if="mode === 'RECAP'" class="data">
      <thead><tr><th>CRITERE</th><th>VALEUR (SUR 5)</th><th>RATE SALARIE</th><th>VALEUR (SUR 5)</th><th>RATE SECTION</th></tr></thead>
      <tbody><tr v-for="r in recap" :key="r.critere">
        <td>{{ r.critere }}</td><td>{{ r.valeur_salarie }}</td>
        <td>{{ '★'.repeat(r.rate_salarie || 0) }}</td>
        <td>{{ r.valeur_section }}</td><td>{{ '★'.repeat(r.rate_section || 0) }}</td>
      </tr></tbody>
    </table>

    <h4>BENCHMARK INTER-SECTIONS PAR CRITÈRE</h4>
    <div class="barre">
      <select v-model="benchmarkCritere"><option value="">— Critère —</option>
        <option v-for="c in criteres" :key="c.id" :value="c.id">{{ c.libelle }}</option></select>
      <button class="btn" @click="lancerBenchmark">ANALYSER</button>
    </div>
    <table v-if="benchmark.length" class="data">
      <thead><tr><th>SECTION</th><th>MOYENNE</th></tr></thead>
      <tbody><tr v-for="b in benchmark" :key="b.section"><td>{{ b.section }}</td><td>{{ b.moyenne }}</td></tr></tbody>
    </table>

    <h4>HISTORIQUE INTER-EXERCICES</h4>
    <table v-if="historique.length" class="data">
      <thead><tr><th>CAMPAGNE</th><th>NOTE N</th><th>NOTE N+1</th><th>STATUT</th></tr></thead>
      <tbody><tr v-for="h in historique" :key="h.campagne">
        <td>{{ h.campagne }}</td><td>{{ h.note_n ?? '—' }}</td><td>{{ h.note_n1 ?? '—' }}</td><td>{{ h.statut_global }}</td>
      </tr></tbody>
    </table>
  </div>
</template>

<style scoped>
.barre { display: flex; gap: 12px; align-items: center; margin-bottom: 12px; }
.barre select { width: 300px; }
h4 { font-size: 12px; color: #0f3b66; margin: 18px 0 8px; }
.barre-critere { display: flex; align-items: center; gap: 8px; margin: 4px 0; font-size: 12px; }
.crit-label { width: 220px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.tracks { flex: 1; }
.track { height: 10px; background: #eef2f7; border-radius: 4px; margin: 2px 0; overflow: hidden; }
.fill { height: 100%; border-radius: 4px; }
.salarie { background: #2563eb; }
.section { background: #f59e0b; }
.legende { display: inline-block; width: 12px; height: 8px; border-radius: 2px; }
</style>
