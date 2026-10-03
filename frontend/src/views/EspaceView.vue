<!-- 2026-10-02 — M2 : bandeau contexte + blocs selon le rôle + campagnes actives. -->
<script setup>
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import api from '../api/client'

const router = useRouter()
const espace = ref(null)

onMounted(async () => { espace.value = (await api.get('/espace')).data })

function ouvrir(campagneId) {
  localStorage.setItem('campagneActive', campagneId)
  router.push('/evaluations/' + campagneId)
}
</script>

<template>
  <div v-if="espace">
    <div class="bandeau">
      <div><b>{{ espace.nom }}</b> — Matricule {{ espace.matricule }}</div>
      <div class="muted">Responsable N+1 : {{ espace.n1 || '—' }}</div>
    </div>
    <h3>CAMPAGNES ACTIVES</h3>
    <p v-if="!espace.campagnes_actives.length" class="muted">Aucune campagne ouverte.</p>
    <div v-for="c in espace.campagnes_actives" :key="c.id" class="bloc">
      <b>{{ c.nom }}</b> (exercice {{ c.exercice }})
      <button class="btn" @click="ouvrir(c.id)">ACCEDER</button>
    </div>
    <div v-if="espace.roles.admin" class="bloc info">
      Vous êtes Admin : consultez PARAMETRAGE, CAMPAGNES et TABLEAUX DE BORD.
    </div>
  </div>
</template>

<style scoped>
.bandeau { background: #fff; border-left: 4px solid #0f3b66; padding: 14px; border-radius: 6px; margin-bottom: 16px; }
.bloc { background: #fff; border-radius: 6px; padding: 14px; margin: 8px 0; display: flex; justify-content: space-between; align-items: center; gap: 12px; }
.info { background: #e0f2fe; }
h3 { margin: 16px 0 8px; font-size: 13px; color: #0f3b66; }
</style>
