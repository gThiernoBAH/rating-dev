<script setup>
/**
 * DataTable.vue — tableau partagé EVALPOINT (inspiré de vusine) :
 * recherche multi-colonnes (insensible casse/accents), tri par colonne (clic
 * en-tête ▲▼), pagination + taille de page, compteur filtré/total, slots de
 * cellule (#cell-<key>="{ row }") et slot #filtres pour la barre d'outils.
 *
 * Colonne : { key, label, align?: 'right'|'center', sortable?: false,
 *             searchable?: false, format?: (valeur, ligne) => string }
 */
import { ref, computed, watch } from 'vue'

const props = defineProps({
  columns: { type: Array, required: true },
  rows: { type: Array, default: () => [] },
  rowKey: { type: [String, Function], default: 'id' },
  loading: { type: Boolean, default: false },
  emptyText: { type: String, default: 'Aucune donnée.' },
  searchPlaceholder: { type: String, default: 'Rechercher dans toutes les colonnes…' },
  defaultSort: { type: Object, default: null },
  pageSize: { type: Number, default: 25 },
  pageSizes: { type: Array, default: () => [25, 50, 100] },
})

const recherche = ref('')
const triCle = ref(props.defaultSort?.key ?? null)
const triSens = ref(props.defaultSort?.dir ?? 1)
const page = ref(1)
const taillePage = ref(props.pageSize)

function normaliser(v) {
  return String(v ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase()
}
function texteCellule(col, row) {
  return col.format ? col.format(row[col.key], row) : (row[col.key] ?? '')
}
const colonnesRecherchables = computed(() => props.columns.filter(c => c.key && c.searchable !== false))

const lignesFiltrees = computed(() => {
  const q = normaliser(recherche.value.trim())
  if (!q) return props.rows
  const mots = q.split(/\s+/)
  return props.rows.filter(row => {
    const texte = colonnesRecherchables.value.map(c => normaliser(texteCellule(c, row))).join(' ')
    return mots.every(m => texte.includes(m))
  })
})

function comparer(a, b) {
  const vide = v => v === null || v === undefined || v === ''
  if (vide(a) && vide(b)) return 0
  if (vide(a)) return 1
  if (vide(b)) return -1
  const na = Number(a), nb = Number(b)
  if (!Number.isNaN(na) && !Number.isNaN(nb) && String(a).trim() !== '' && String(b).trim() !== '') return na - nb
  return String(a).localeCompare(String(b), 'fr', { numeric: true, sensitivity: 'base' })
}

const lignesTriees = computed(() => {
  if (!triCle.value) return lignesFiltrees.value
  return [...lignesFiltrees.value].sort((a, b) =>
    comparer(a[triCle.value], b[triCle.value]) * triSens.value)
})

const nbPages = computed(() => Math.max(1, Math.ceil(lignesTriees.value.length / taillePage.value)))
const lignesPage = computed(() => {
  const debut = (page.value - 1) * taillePage.value
  return lignesTriees.value.slice(debut, debut + taillePage.value)
})
const premier = computed(() => lignesTriees.value.length ? (page.value - 1) * taillePage.value + 1 : 0)
const dernier = computed(() => Math.min(page.value * taillePage.value, lignesTriees.value.length))

const pagesVisibles = computed(() => {
  const n = nbPages.value, p = page.value
  if (n <= 7) return Array.from({ length: n }, (_, i) => i + 1)
  const pages = new Set([1, n, p - 1, p, p + 1])
  const liste = [...pages].filter(x => x >= 1 && x <= n).sort((a, b) => a - b)
  const resultat = []
  liste.forEach((x, i) => {
    if (i && x - liste[i - 1] > 1) resultat.push('…' + x)
    resultat.push(x)
  })
  return resultat
})

watch([recherche, taillePage, () => props.rows], () => { page.value = 1 })
watch(nbPages, n => { if (page.value > n) page.value = n })

function trierPar(col) {
  if (col.sortable === false || !col.key) return
  if (triCle.value === col.key) triSens.value *= -1
  else { triCle.value = col.key; triSens.value = 1 }
  page.value = 1
}
function cle(row, index) {
  return typeof props.rowKey === 'function' ? props.rowKey(row, index) : (row[props.rowKey] ?? index)
}
function ariaSort(col) {
  if (triCle.value !== col.key) return 'none'
  return triSens.value === 1 ? 'ascending' : 'descending'
}
</script>

<template>
  <div class="data-table">
    <div class="dt-barre">
      <div class="dt-recherche">
        <svg class="dt-loupe" viewBox="0 0 24 24" width="16" height="16" aria-hidden="true">
          <circle cx="11" cy="11" r="7" fill="none" stroke="currentColor" stroke-width="2" />
          <line x1="16.5" y1="16.5" x2="21" y2="21" stroke="currentColor" stroke-width="2" stroke-linecap="round" />
        </svg>
        <input v-model="recherche" type="search" :placeholder="searchPlaceholder"
          :title="`Recherche dans : ${colonnesRecherchables.map(c => c.label).join(', ')}`"
          aria-label="Rechercher dans le tableau" />
      </div>
      <slot name="filtres" />
      <span class="dt-compte">
        {{ lignesFiltrees.length.toLocaleString('fr-FR') }} / {{ rows.length.toLocaleString('fr-FR') }}
      </span>
    </div>

    <div v-if="loading" class="dt-etat">Chargement…</div>

    <div v-else class="dt-cadre">
      <table>
        <thead>
          <tr>
            <th v-for="col in columns" :key="col.key || col.label"
              :class="{ triable: col.sortable !== false && col.key, droite: col.align === 'right',
                        centre: col.align === 'center', actif: triCle === col.key }"
              :title="col.sortable !== false && col.key ? `Trier par ${col.label}` : ''"
              :aria-sort="ariaSort(col)">
              <button v-if="col.sortable !== false && col.key" type="button" class="dt-tri" @click="trierPar(col)">
                {{ col.label }}
                <span class="dt-fleche" aria-hidden="true">{{ triCle === col.key ? (triSens === 1 ? '▲' : '▼') : '↕' }}</span>
              </button>
              <template v-else>{{ col.label }}</template>
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(row, i) in lignesPage" :key="cle(row, i)">
            <td v-for="col in columns" :key="col.key || col.label"
              :class="{ droite: col.align === 'right', centre: col.align === 'center' }">
              <slot :name="`cell-${col.key}`" :row="row" :value="row[col.key]">
                {{ col.format ? col.format(row[col.key], row) : (row[col.key] ?? '—') }}
              </slot>
            </td>
          </tr>
          <tr v-if="!lignesPage.length">
            <td :colspan="columns.length" class="dt-vide">
              {{ rows.length ? 'Aucune ligne ne correspond à la recherche.' : emptyText }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div v-if="!loading && lignesTriees.length > pageSizes[0]" class="dt-pagination">
      <span class="dt-plage">
        {{ premier.toLocaleString('fr-FR') }}–{{ dernier.toLocaleString('fr-FR') }}
        sur {{ lignesTriees.length.toLocaleString('fr-FR') }}
      </span>
      <div class="dt-pages">
        <button type="button" class="dt-page" :disabled="page === 1" title="Page précédente" @click="page--">‹</button>
        <template v-for="p in pagesVisibles" :key="p">
          <span v-if="typeof p === 'string'" class="dt-ellipse">…</span>
          <button v-else type="button" :class="['dt-page', { courante: p === page }]"
            :aria-current="p === page ? 'page' : null" :title="`Aller à la page ${p}`" @click="page = p">{{ p }}</button>
        </template>
        <button type="button" class="dt-page" :disabled="page === nbPages" title="Page suivante" @click="page++">›</button>
      </div>
      <label class="dt-taille">
        Lignes par page
        <select v-model.number="taillePage" title="Nombre de lignes affichées par page">
          <option v-for="t in pageSizes" :key="t" :value="t">{{ t }}</option>
        </select>
      </label>
    </div>
  </div>
</template>

<style scoped>
.dt-barre { display: flex; align-items: center; gap: var(--space-3); margin-bottom: var(--space-3); flex-wrap: wrap; }
.dt-recherche { position: relative; flex: 1; min-width: 220px; }
.dt-loupe { position: absolute; left: 10px; top: 50%; transform: translateY(-50%); color: var(--color-text-muted); pointer-events: none; }
.dt-recherche input {
  width: 100%; height: 36px; padding: 0 var(--space-3) 0 32px;
  border: 1px solid var(--color-border); border-radius: var(--radius-md);
  font-size: var(--font-size-sm); background: var(--color-surface); font-family: inherit;
}
.dt-recherche input:focus { outline: 2px solid var(--color-brand); outline-offset: -1px; }
.dt-compte { font-size: var(--font-size-xs); color: var(--color-text-muted); white-space: nowrap; }
.dt-etat { color: var(--color-text-muted); padding: var(--space-4) 0; }
.dt-cadre { overflow-x: auto; background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-lg); }
table { width: 100%; border-collapse: collapse; }
th {
  text-align: left; background: var(--color-brand-light); color: var(--color-brand-dark);
  font-size: var(--font-size-xs); font-weight: 700; padding: var(--space-3);
  white-space: nowrap; user-select: none;
}
td { padding: var(--space-3); border-top: 1px solid var(--color-border); font-size: var(--font-size-sm); }
tbody tr:hover td { background: #F8FAFC; }
.droite { text-align: right; } th.droite .dt-tri { justify-content: flex-end; }
.centre { text-align: center; } th.centre .dt-tri { justify-content: center; }
.dt-tri {
  display: inline-flex; align-items: center; gap: 4px; width: 100%;
  border: none; background: none; padding: 0; font: inherit; color: inherit; cursor: pointer;
}
.dt-tri:hover { text-decoration: underline; }
.dt-tri:focus-visible { outline: 2px solid var(--color-brand); outline-offset: 2px; border-radius: 2px; }
.dt-fleche { font-size: 10px; opacity: 0.35; }
th.actif .dt-fleche { opacity: 1; }
.dt-vide { text-align: center; color: var(--color-text-muted); padding: var(--space-6) !important; }
.dt-pagination {
  display: flex; align-items: center; justify-content: space-between; gap: var(--space-3);
  flex-wrap: wrap; margin-top: var(--space-3); font-size: var(--font-size-xs); color: var(--color-text-muted);
}
.dt-pages { display: flex; align-items: center; gap: 4px; }
.dt-page {
  min-width: 30px; height: 30px; padding: 0 var(--space-2); border: 1px solid var(--color-border);
  border-radius: var(--radius-md); background: var(--color-surface); color: var(--color-text);
  font-size: var(--font-size-xs); font-weight: 600; cursor: pointer; font-family: inherit;
  transition: background-color .15s ease, border-color .15s ease;
}
.dt-page:hover:not(:disabled) { border-color: var(--color-brand); background: var(--color-brand-light); }
.dt-page.courante { background: var(--color-brand); border-color: var(--color-brand); color: var(--color-text-inverse); }
.dt-page:disabled { opacity: .4; cursor: not-allowed; }
.dt-page:focus-visible { outline: 2px solid var(--color-brand); outline-offset: 2px; }
.dt-ellipse { padding: 0 4px; }
.dt-taille select {
  margin-left: var(--space-2); width: 72px; padding: 0 8px;   /* PATCH 12 : le chiffre était avalé */
  height: 30px; border: 1px solid var(--color-border);
  border-radius: var(--radius-md); background: var(--color-surface); font-family: inherit;
}
</style>
