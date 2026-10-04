<!-- PATCH 10 — benchmark anonymisé inter-sections (Admin) : avancement par
     section, sections < 5 fiches masquées pour l'anonymat. -->
<script setup>
import { onMounted, ref } from 'vue'
import api from '../api/client'

const sections = ref([])
const erreur = ref('')

async function charger() {
  try { sections.value = (await api.get('/bench/sections')).data }
  catch (e) { erreur.value = e.response?.data?.detail || 'Chargement impossible.' }
}
onMounted(charger)

function barre(v) { return { height: '100%', width: (v || 0) + '%', transition: 'width .3s' } }
</script>

<template>
  <div>
    <h3>BENCHMARK INTER-SECTIONS (ANONYMISÉ)</h3>
    <p class="muted">Agrégats sur toutes les fiches évaluées. Les sections de moins de 5 fiches
      sont regroupées sous « Section anonymisée » pour préserver la confidentialité.</p>
    <div v-if="erreur" class="error">{{ erreur }}</div>
    <table class="data">
      <thead><tr>
        <th>SECTION</th><th>FICHES</th><th>AUTO-ÉVAL. CLÔTURÉES</th>
        <th>ÉVAL. N+1 CLÔTURÉES</th><th>APPROUVÉES</th>
      </tr></thead>
      <tbody>
        <tr v-for="s in sections" :key="s.section" :class="{ anonyme: s.anonyme }">
          <td>{{ s.section }}</td>
          <td>{{ s.nb_fiches }}</td>
          <td><div class="barre-g"><div :style="barre(s.pct_n)" style="background: var(--color-brand)"></div></div>{{ s.pct_n }} %</td>
          <td><div class="barre-g"><div :style="barre(s.pct_n1)" style="background: var(--color-orange)"></div></div>{{ s.pct_n1 }} %</td>
          <td><div class="barre-g"><div :style="barre(s.pct_approuvees)" style="background: var(--color-vert)"></div></div>{{ s.pct_approuvees }} %</td>
        </tr>
      </tbody>
    </table>
    <div v-if="!sections.length" class="muted">Aucune donnée à comparer pour l'instant.</div>
  </div>
</template>

<style scoped>
h3 { font-size: 13px; color: var(--color-brand-dark); margin-bottom: 8px; }
.muted { color: var(--color-text-muted); font-size: 12px; }
.barre-g { display: inline-block; vertical-align: middle; width: 120px; height: 8px; background: var(--color-border); border-radius: 4px; overflow: hidden; margin-right: 8px; }
tr.anonyme td { color: var(--color-text-muted); font-style: italic; }
</style>
