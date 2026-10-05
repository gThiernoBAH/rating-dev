<!-- PATCH 12 — benchmark inter-sections (Admin) : TOUTES les sections affichées
     (plus d'anonymisation), recherche + tri via DataTable. -->
<script setup>
import { onMounted, ref } from 'vue'
import api from '../api/client'
import DataTable from '../components/DataTable.vue'

const sections = ref([])
const erreur = ref('')

async function charger() {
  try { sections.value = (await api.get('/bench/sections')).data }
  catch (e) { erreur.value = e.response?.data?.detail || 'Chargement impossible.' }
}
onMounted(charger)

function barre(v) { return { height: '100%', width: (v || 0) + '%', transition: 'width .3s' } }
const COLONNES = [
  { key: 'section', label: 'Section' },
  { key: 'nb_fiches', label: 'Fiches', align: 'center' },
  { key: 'pct_n', label: 'Auto-éval. clôturées (%)', align: 'center' },
  { key: 'pct_n1', label: 'Éval. N+1 clôturées (%)', align: 'center' },
  { key: 'pct_approuvees', label: 'Approuvées (%)', align: 'center' },
]
</script>

<template>
  <div>
    <h3>BENCHMARK INTER-SECTIONS</h3>
    <p class="muted">Agrégats sur toutes les fiches évaluées : avancement par section
      (auto-évaluations, évaluations N+1, approbations).</p>
    <div v-if="erreur" class="error">{{ erreur }}</div>
    <DataTable :columns="COLONNES" :rows="sections" :row-key="'section'"
      search-placeholder="Rechercher une section…">
      <template #cell-pct_n="{ row }">
        <div class="barre-g"><div :style="barre(row.pct_n)" style="background: var(--color-brand)"></div></div>{{ row.pct_n }} %
      </template>
      <template #cell-pct_n1="{ row }">
        <div class="barre-g"><div :style="barre(row.pct_n1)" style="background: var(--color-orange)"></div></div>{{ row.pct_n1 }} %
      </template>
      <template #cell-pct_approuvees="{ row }">
        <div class="barre-g"><div :style="barre(row.pct_approuvees)" style="background: var(--color-vert)"></div></div>{{ row.pct_approuvees }} %
      </template>
    </DataTable>
    <div v-if="!sections.length && !erreur" class="muted">Aucune donnée à comparer pour l'instant.</div>
  </div>
</template>

<style scoped>
h3 { font-size: 13px; color: var(--color-brand-dark); margin-bottom: 8px; }
.muted { color: var(--color-text-muted); font-size: 12px; }
.barre-g { display: inline-block; vertical-align: middle; width: 120px; height: 8px; background: var(--color-border); border-radius: 4px; overflow: hidden; margin-right: 8px; }
</style>
