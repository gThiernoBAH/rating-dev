<!-- 2026-10-03 PATCH5 — M7 : DataTable + filtre section + retardataires
     triables + statistiques visuelles d'un salarié (matricule/salarié)
     pour Admin et N+1 : graphe barres + récap étoiles (cf. navigation API). -->
<script setup>
import { onMounted, ref, computed, watch } from 'vue'
import api from '../api/client'
import DataTable from '../components/DataTable.vue'

const campagnes = ref([])
const campagneId = ref('')
const data = ref(null)
const filtreSection = ref('')
const salaries = ref([])
const salarieId = ref('')
const graphe = ref([])
const recap = ref([])

onMounted(async () => {
  campagnes.value = (await api.get('/campagnes')).data
  salaries.value = (await api.get('/navigation/salaries')).data
})

async function charger() {
  if (!campagneId.value) return
  data.value = (await api.get('/dashboard/avancement', { params: { campagne_id: campagneId.value } })).data
}
watch(campagneId, charger)

const sectionsFiltrees = computed(() =>
  (data.value?.sections || []).filter(s => !filtreSection.value || s.section === filtreSection.value))

const COLONNES = [
  { key: 'section', label: 'Section' },
  { key: 'total', label: 'Fiches', align: 'center' },
  { key: 'pct_n', label: '% Auto-éval (N)', format: v => (v ?? 0) + ' %' },
  { key: 'pct_n1', label: '% Éval (N+1)', format: v => (v ?? 0) + ' %' },
  { key: 'pct_n2', label: '% Approb (N+2)', format: v => (v ?? 0) + ' %' },
]

const COLONNES_RETARD = [
  { key: 'matricule', label: 'Matricule' },
  { key: 'nom', label: 'Nom' },
]

async function afficherSalarie() {
  if (!salarieId.value || !campagneId.value) return
  const params = { salarie_id: salarieId.value, campagne_id: campagneId.value }
  graphe.value = (await api.get('/navigation/graphe', { params })).data
  recap.value = (await api.get('/navigation/recap', { params })).data
}
const etoiles = (n) => n ? '★'.repeat(n) + '☆'.repeat(5 - n) : '—'
</script>

<template>
  <div>
    <div class="barre">
      <select v-model="campagneId" title="Choisir la campagne à analyser">
        <option value="">— Campagne —</option>
        <option v-for="c in campagnes" :key="c.id" :value="c.id">{{ c.nom }} ({{ c.exercice }})</option>
      </select>
    </div>
    <div v-if="data && data.erreur" class="error">{{ data.erreur }}</div>
    <div v-if="data && !data.erreur">
      <h4>AVANCEMENT PAR SECTION</h4>
      <DataTable :columns="COLONNES" :rows="sectionsFiltrees" :row-key="'section'"
        search-placeholder="Rechercher une section…">
        <template #filtres>
          <select v-model="filtreSection" title="Filtrer sur une section">
            <option value="">— Toutes —</option>
            <option v-for="s in data.sections" :key="s.section" :value="s.section">{{ s.section }}</option>
          </select>
        </template>
      </DataTable>

      <h4>RETARDATAIRES</h4>
      <p v-if="!data.retardataires.length" class="muted">Aucun.</p>
      <DataTable v-else :columns="COLONNES_RETARD" :rows="data.retardataires" :row-key="'matricule'"
        search-placeholder="Rechercher un retardataire…" />

      <h4>ANOMALIES</h4>
      <p>Salariés sans N+1 : <b>{{ data.anomalies.sans_n1 }}</b> · Hors évaluation : <b>{{ data.anomalies.hors_evaluation }}</b></p>

      <h4>STATISTIQUES D'UN SALARIÉ</h4>
      <div class="barre">
        <select v-model="salarieId" @change="afficherSalarie" style="width:340px"
          title="Choisir un salarié pour visualiser son évaluation vs sa section">
          <option value="">— Matricule / Salarié —</option>
          <option v-for="s in salaries" :key="s.id" :value="s.id">{{ s.matricule }} – {{ s.nom }}</option>
        </select>
      </div>
      <template v-if="salarieId && graphe.length">
        <div class="graphe">
          <div v-for="g in graphe" :key="g.critere" class="barre-critere">
            <div class="crit-label" :title="g.critere">{{ g.critere }}</div>
            <div class="tracks">
              <div class="track"><div class="fill salarie" :style="{ width: (g.salarie / 5 * 100) + '%' }"></div></div>
              <div class="track"><div class="fill section" :style="{ width: (g.section / 5 * 100) + '%' }"></div></div>
            </div>
            <span class="vals">{{ g.salarie }} / {{ g.section }}</span>
          </div>
          <p class="muted"><span class="legende salarie">&nbsp;</span> Salarié &nbsp; <span class="legende section">&nbsp;</span> Moyenne section</p>
        </div>
        <table class="data">
          <thead><tr><th>CRITÈRE</th><th>NOTE SALARIÉ (/5)</th><th>ÉTOILES</th><th>NOTE SECTION (/5)</th><th>ÉTOILES</th></tr></thead>
          <tbody><tr v-for="r in recap" :key="r.critere">
            <td>{{ r.critere }}</td><td>{{ r.valeur_salarie }}</td><td>{{ etoiles(r.rate_salarie) }}</td>
            <td>{{ r.valeur_section }}</td><td>{{ etoiles(r.rate_section) }}</td>
          </tr></tbody>
        </table>
      </template>
      <p v-else-if="salarieId" class="muted">Aucune donnée d'évaluation pour ce salarié sur cette campagne.</p>
    </div>
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
.legende { display: inline-block; width: 12px; height: 8px; border-radius: 2px; }
</style>
