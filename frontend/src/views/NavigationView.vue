<!-- 2026-10-03 PATCH5 — M3bis : le salarié est AUTO-SÉLECTIONNÉ (son propre
     matricule/nom) ; le sélecteur reste pour l'Admin/managers (périmètre).
     Critères du benchmark chargés pour tous via /navigation/criteres.
     Benchmark avec barres visuelles. Consultation seule. -->
<script setup>
import { computed, onMounted, ref } from 'vue'   // PATCH 12
import api from '../api/client'
import { useAuth } from '../stores/auth'

const auth = useAuth()
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
const sections = ref([])   // PATCH 12
const filtreSection = ref('')   // PATCH 12

async function afficher() {
  if (!salarieId.value || !campagneId.value) return
  const params = { salarie_id: salarieId.value, campagne_id: campagneId.value }
  graphe.value = (await api.get('/navigation/graphe', { params })).data
  recap.value = (await api.get('/navigation/recap', { params })).data
  historique.value = (await api.get('/navigation/historique', { params: { salarie_id: salarieId.value } })).data
}

onMounted(async () => {
  salaries.value = (await api.get('/navigation/salaries')).data
  try { sections.value = (await api.get('/navigation/sections')).data } catch { sections.value = [] }   // PATCH 12
  criteres.value = (await api.get('/navigation/criteres')).data
  try {
    const { data } = await api.get('/espace')
    const actives = data.campagnes_actives || []
    campagneId.value = actives[0]?.id || ''
  } catch { /* Admin sans campagne */ }
  // Le salarié voit SON graphe direct : son matricule est auto-renseigné.
  const moi = salaries.value.find(s => s.matricule === auth.me?.matricule)
  if (moi) { salarieId.value = moi.id; await afficher() }
})

const salariesAffiches = computed(() => filtreSection.value   // PATCH 12
  ? salaries.value.filter(s => s.section_id === filtreSection.value)
  : salaries.value)
function surFiltreSection() {   // PATCH 12
  if (!salariesAffiches.value.some(s => s.id === salarieId.value)) {
    salarieId.value = salariesAffiches.value[0]?.id || ''
    afficher()
  }
}
async function lancerBenchmark() {
  if (!benchmarkCritere.value || !campagneId.value) return
  benchmark.value = (await api.get('/navigation/benchmark', {
    params: { critere_id: benchmarkCritere.value, campagne_id: campagneId.value }
  })).data
}

const etoiles = (n) => n ? '★'.repeat(n) + '☆'.repeat(5 - n) : '—'
const maxBench = () => Math.max(...benchmark.value.map(b => b.moyenne || 0), 5)
</script>

<template>
  <div>
    <div class="barre">
      <select v-model="filtreSection" class="sel-large" @change="surFiltreSection"
        title="Filtrer par section (sections de votre périmètre)">
        <option value="">— Toutes les sections —</option>
        <option v-for="sc in sections" :key="sc.id" :value="sc.id">{{ sc.libelle }}</option>
      </select>
      <select v-model="salarieId" @change="afficher" class="sel-large"
        title="Salarié affiché (vous par défaut ; managers : votre périmètre)">
        <option v-for="s in salariesAffiches" :key="s.id" :value="s.id">{{ s.matricule }} – {{ s.nom }}</option>   <!-- PATCH 12 -->
      </select>
      <div class="tabs" style="margin:0">
        <div class="tab" :class="{ active: mode === 'GRAPHE' }" title="Vue graphique par critère" @click="mode = 'GRAPHE'">GRAPHE</div>
        <div class="tab" :class="{ active: mode === 'RECAP' }" title="Vue tableau des notes et étoiles" @click="mode = 'RECAP'">RECAP</div>
      </div>
    </div>

    <h4 v-if="mode === 'GRAPHE'">REPRÉSENTATION ÉVALUATION DU SALARIÉ PAR RAPPORT À SA SECTION</h4>
    <div v-if="mode === 'GRAPHE'" class="graphe">
      <div v-for="g in graphe" :key="g.critere" class="barre-critere">
        <div class="crit-label" :title="g.critere">{{ g.critere }}</div>
        <div class="tracks">
          <div class="track"><div class="fill salarie" :style="{ width: (g.salarie / 5 * 100) + '%' }"></div></div>
          <div class="track"><div class="fill section" :style="{ width: (g.section / 5 * 100) + '%' }"></div></div>
        </div>
        <span class="vals">{{ g.salarie }} / {{ g.section }}</span>
      </div>
      <p class="muted"><span class="legende salarie">&nbsp;</span> Salarié &nbsp; <span class="legende section">&nbsp;</span> Section</p>
      <p v-if="!graphe.length" class="muted">Aucune donnée pour cette campagne.</p>
    </div>

    <h4 v-if="mode === 'RECAP'">RÉCAPITULATIF DES NOTES D'ÉVALUATION DU SALARIÉ PAR RAPPORT À SA SECTION</h4>
    <table v-if="mode === 'RECAP' && recap.length" class="data">
      <thead><tr><th>CRITERE</th><th>VALEUR (SUR 5)</th><th>RATE SALARIE</th><th>VALEUR (SUR 5)</th><th>RATE SECTION</th></tr></thead>
      <tbody><tr v-for="r in recap" :key="r.critere">
        <td>{{ r.critere }}</td><td>{{ r.valeur_salarie }}</td>
        <td>{{ etoiles(r.rate_salarie) }}</td>
        <td>{{ r.valeur_section }}</td><td>{{ etoiles(r.rate_section) }}</td>
      </tr></tbody>
    </table>

    <h4>BENCHMARK INTER-SECTIONS PAR CRITÈRE</h4>
    <div class="barre">
      <select v-model="benchmarkCritere" class="sel-large"
        title="Critère à comparer entre les sections (moyennes des évaluations N+1)">
        <option value="">— Critère —</option>
        <option v-for="c in criteres" :key="c.id" :value="c.id">{{ c.libelle }}</option>
      </select>
      <button class="btn" title="Comparer toutes les sections sur ce critère" @click="lancerBenchmark">ANALYSER</button>
    </div>
    <div v-if="benchmark.length" class="benchmark">
      <div v-for="b in benchmark" :key="b.section" class="barre-critere">
        <div class="crit-label" :title="b.section">{{ b.section }}</div>
        <div class="tracks">
          <div class="track"><div class="fill bench" :style="{ width: (b.moyenne / maxBench() * 100) + '%' }"></div></div>
        </div>
        <span class="vals">{{ b.moyenne }}</span>
      </div>
    </div>
    <p v-else-if="benchmarkCritere" class="muted">Aucune donnée pour ce critère.</p>

    <h4>HISTORIQUE INTER-EXERCICES</h4>
    <table v-if="historique.length" class="data">
      <thead><tr><th>CAMPAGNE</th><th>NOTE N</th><th>NOTE N+1</th><th>STATUT</th></tr></thead>
      <tbody><tr v-for="h in historique" :key="h.campagne">
        <td>{{ h.campagne }}</td><td>{{ h.note_n ?? '—' }}</td>
        <td>{{ h.note_n1 ?? '—' }}</td><td>{{ h.statut_global }}</td>
      </tr></tbody>
    </table>
    <p v-else class="muted">Historique disponible dès la 2ᵉ campagne.</p>
  </div>
</template>

<style scoped>
.barre { display: flex; gap: 12px; align-items: center; margin-bottom: 12px; }
h4 { font-size: 12px; color: var(--color-brand-dark); margin: 18px 0 8px; }
.barre-critere { display: flex; align-items: center; gap: 8px; margin: 4px 0; font-size: 12px; }
.crit-label { width: 220px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.tracks { flex: 1; }
.track { height: 10px; background: var(--color-bg); border-radius: 4px; margin: 2px 0; overflow: hidden; }
.fill { height: 100%; border-radius: 4px; }
.salarie { background: var(--color-brand); }
.section { background: var(--color-orange); }
.bench { background: var(--color-brand); }
.legende { display: inline-block; width: 12px; height: 8px; border-radius: 2px; }

/* ---------- PATCH 8 — mobile ---------- */
.sel-large { width: 340px; max-width: 100%; }
@media (max-width: 768px) {
  .barre { flex-wrap: wrap; }
  .sel-large { width: 100%; }
  .barre-critere { flex-wrap: wrap; }
  .crit-label { width: 100%; white-space: normal; text-overflow: clip; }
  .vals { margin-left: auto; }
}
</style>
