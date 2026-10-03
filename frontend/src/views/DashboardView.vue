<!-- 2026-10-02 — M7 : avancement (% N / N+1 / N+2 par section), retardataires,
     anomalies. Admin + N+1. Exports Excel/PDF prévus (évolution). -->
<script setup>
import { onMounted, ref } from 'vue'
import api from '../api/client'

const campagnes = ref([])
const campagneId = ref('')
const data = ref(null)

onMounted(async () => { campagnes.value = (await api.get('/campagnes')).data })

async function charger() {
  if (!campagneId.value) return
  data.value = (await api.get('/dashboard/avancement', { params: { campagne_id: campagneId.value } })).data
}
</script>

<template>
  <div>
    <div class="barre">
      <select v-model="campagneId" @change="charger">
        <option value="">— Campagne —</option>
        <option v-for="c in campagnes" :key="c.id" :value="c.id">{{ c.nom }} ({{ c.exercice }})</option>
      </select>
    </div>
    <div v-if="data">
      <table class="data">
        <thead><tr><th>SECTION</th><th>FICHES</th><th>% AUTO-EVAL (N)</th><th>% EVAL (N+1)</th><th>% APPROB (N+2)</th></tr></thead>
        <tbody><tr v-for="s in data.sections" :key="s.section">
          <td>{{ s.section }}</td><td>{{ s.total }}</td>
          <td>{{ s.pct_n }}%</td><td>{{ s.pct_n1 }}%</td><td>{{ s.pct_n2 }}%</td>
        </tr></tbody>
      </table>
      <h4>RETARDATAIRES</h4>
      <p v-if="!data.retardataires.length" class="muted">Aucun.</p>
      <table v-else class="data"><tbody><tr v-for="r in data.retardataires" :key="r.matricule">
        <td>{{ r.matricule }} — {{ r.nom }}</td></tr></tbody></table>
      <h4>ANOMALIES</h4>
      <p>Salariés sans N+1 : <b>{{ data.anomalies.sans_n1 }}</b> · Hors évaluation : <b>{{ data.anomalies.hors_evaluation }}</b></p>
    </div>
  </div>
</template>

<style scoped>
.barre { margin-bottom: 12px; } .barre select { width: 320px; }
h4 { font-size: 12px; color: #0f3b66; margin: 16px 0 6px; }
</style>
