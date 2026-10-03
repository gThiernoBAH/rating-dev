<!-- 2026-10-02 — M3 : tableau à 9 colonnes, sections N / N+1 / N+2 selon le rôle,
     clic sur ligne -> fiche M4. Blocages gérés côté API (§6.5). -->
<script setup>
import { onMounted, ref, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import api from '../api/client'
import { useAuth } from '../stores/auth'

const route = useRoute()
const router = useRouter()
const auth = useAuth()
const fiches = ref([])
const erreur = ref('')

onMounted(async () => {
  try { fiches.value = (await api.get('/evaluations', { params: { campagne_id: route.params.campagneId } })).data }
  catch (e) { erreur.value = e.response?.data?.detail || 'Erreur de chargement.' }
})

const sections = computed(() => {
  const sec = { N: [], 'N+1': [], 'N+2': [], ADMIN: [] }
  fiches.value.forEach(f => sec[f.role]?.push(f))
  return [
    { code: 'N', titre: 'AUTO-EVALUATIONS (N)', liste: sec.N },
    { code: 'N+1', titre: 'EVALUATIONS (N+1)', liste: sec['N+1'] },
    { code: 'N+2', titre: 'APPROBATIONS (N+2)', liste: sec['N+2'] },
    { code: 'ADMIN', titre: 'TOUTES LES FICHES (ADMIN)', liste: sec.ADMIN },
  ].filter(s => s.liste.length)
})

function ouvrir(f) { router.push('/fiche/' + f.id) }
</script>

<template>
  <div>
    <div v-if="erreur" class="error">{{ erreur }}</div>
    <section v-for="s in sections" :key="s.code" style="margin-bottom:24px">
      <h3>{{ s.titre }} <span class="muted">({{ s.liste.length }})</span></h3>
      <table class="data">
        <thead><tr>
          <th>EXERCICE / N°</th><th>SECTION</th><th>MATRICULE</th><th>SALARIE</th>
          <th>DATE EVAL.</th><th>STATUT N</th><th>STATUT N+1</th><th>STATUT N+2</th><th>GLOBAL</th>
        </tr></thead>
        <tbody>
          <tr v-for="f in s.liste" :key="f.id" style="cursor:pointer" @click="ouvrir(f)">
            <td>{{ f.numero }}</td><td>{{ f.section }}</td><td>{{ f.matricule }}</td><td>{{ f.salaries }}</td>
            <td>{{ f.date_evaluation }}</td>
            <td :class="{ locked: f.statut_n === 'Clôturée' }">{{ f.statut_n }}</td>
            <td :class="{ locked: f.statut_n1 === 'Clôturée' }">{{ f.statut_n1 }}</td>
            <td :class="{ locked: f.statut_n2 === 'Clôturée' }">{{ f.statut_n2 }}</td>
            <td>{{ f.statut_global }}</td>
          </tr>
        </tbody>
      </table>
    </section>
    <p v-if="!sections.length" class="muted">Aucune fiche à afficher pour cette campagne.</p>
  </div>
</template>

<style scoped>h3 { font-size: 13px; color: #0f3b66; margin: 12px 0 6px; }</style>
