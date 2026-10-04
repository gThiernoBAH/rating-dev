<!-- PATCH 10 — check-ins trimestriels N/N+1 : liste du périmètre, création,
     clôture. Mobile : cartes (adaptation patch 8). -->
<script setup>
import { onMounted, ref } from 'vue'
import { Plus, Check, Lock } from 'lucide-vue-next'
import api from '../api/client'
import { useConfirm } from '../composables/useConfirm'

const { confirm } = useConfirm()
const liste = ref([])
const collaborateurs = ref([])
const erreur = ref('')
const message = ref('')
const estMobile = window.matchMedia('(max-width: 768px)').matches
const annee = ref(new Date().getFullYear())
const trimestre = ref(Math.min(4, Math.floor(new Date().getMonth() / 3) + 1))
const modale = ref(false)
const forme = ref({ salarie_id: null, points_forts: '', axes_amelioration: '' })

async function charger() {
  erreur.value = ''
  try {
    const [l, c] = await Promise.all([
      api.get('/checkins', { params: { trimestre: trimestre.value, annee: annee.value } }),
      api.get('/checkins/collaborateurs'),
    ])
    liste.value = l.data
    collaborateurs.value = c.data
  } catch (e) { erreur.value = e.response?.data?.detail || 'Chargement impossible.' }
}
onMounted(charger)

function ouvrir() { forme.value = { salarie_id: null, points_forts: '', axes_amelioration: '' }; modale.value = true }

async function enregistrer() {
  if (!forme.value.salarie_id) { erreur.value = 'Choisissez un collaborateur.'; return }
  if (!forme.value.points_forts.trim() || !forme.value.axes_amelioration.trim()) {
    erreur.value = 'Points forts et axes d\'amélioration obligatoires.'; return
  }
  try {
    await api.post('/checkins', { ...forme.value, trimestre: trimestre.value, annee: annee.value })
    modale.value = false; message.value = 'Check-in enregistré.'; await charger()
  } catch (e) { erreur.value = e.response?.data?.detail }
}

async function cloturer(c) {
  const ok = await confirm({
    title: 'Clôturer le check-in',
    message: `Clôturer le check-in de ${c.nom} (T${c.trimestre} ${c.annee}) ? La date du jour sera retenue comme date de réunion.`,
    confirmLabel: 'Clôturer',
  })
  if (!ok) return
  try {
    await api.post('/checkins/' + c.id + '/cloturer')
    message.value = 'Check-in clôturé.'; await charger()
  } catch (e) { erreur.value = e.response?.data?.detail }
}
</script>

<template>
  <div>
    <h3>CHECK-INS TRIMESTRIELS</h3>
    <div class="forme">
      <div class="field"><label>TRIMESTRE</label>
        <select v-model="trimestre" @change="charger">
          <option :value="1">T1</option><option :value="2">T2</option>
          <option :value="3">T3</option><option :value="4">T4</option>
        </select></div>
      <div class="field"><label>ANNÉE</label><input type="number" v-model="annee" @change="charger" /></div>
      <button class="btn" title="Planifier un nouveau check-in trimestriel" @click="ouvrir">
        <Plus :size="14" /> NOUVEAU CHECK-IN</button>
    </div>
    <div v-if="message" class="ok">{{ message }}</div>
    <div v-if="erreur" class="error">{{ erreur }}</div>

    <table v-if="!estMobile" class="data">
      <thead><tr><th>COLLABORATEUR</th><th>TRIMESTRE</th><th>POINTS FORTS</th><th>AXES D'AMÉLIORATION</th><th>DÉCISION</th><th>ACTIONS</th></tr></thead>
      <tbody>
        <tr v-for="c in liste" :key="c.id">
          <td>{{ c.matricule }} — {{ c.nom }}</td>
          <td>T{{ c.trimestre }} {{ c.annee }}</td>
          <td>{{ c.points_forts }}</td>
          <td>{{ c.axes_amelioration }}</td>
          <td><span class="badge-statut" :class="c.decision === 'Clôturé' ? 'statut-vert' : 'statut-orange'">{{ c.decision }}</span></td>
          <td><button v-if="c.decision !== 'Clôturé'" class="icon-btn" style="color: var(--color-vert)"
            title="Clôturer ce check-in (date du jour)" @click="cloturer(c)"><Lock :size="15" /></button></td>
        </tr>
      </tbody>
    </table>

    <div v-else>
      <div v-for="c in liste" :key="c.id" class="card" style="margin-bottom:10px;">
        <div><b>{{ c.matricule }} — {{ c.nom }}</b> · T{{ c.trimestre }} {{ c.annee }}</div>
        <div style="font-size:12px; margin-top:6px;"><b>Points forts :</b> {{ c.points_forts }}</div>
        <div style="font-size:12px; margin-top:4px;"><b>Axes :</b> {{ c.axes_amelioration }}</div>
        <div style="margin-top:8px; display:flex; gap:8px; align-items:center;">
          <span class="badge-statut" :class="c.decision === 'Clôturé' ? 'statut-vert' : 'statut-orange'">{{ c.decision }}</span>
          <button v-if="c.decision !== 'Clôturé'" class="icon-btn" style="color: var(--color-vert)"
            title="Clôturer ce check-in" @click="cloturer(c)"><Lock :size="15" /></button>
        </div>
      </div>
      <div v-if="!liste.length" style="color: var(--color-text-muted); font-size: 12px;">Aucun check-in ce trimestre.</div>
    </div>

    <div v-if="modale" class="overlay" @click.self="modale = false"></div>
    <div v-if="modale" class="modale">
      <h4>NOUVEAU CHECK-IN — T{{ trimestre }} {{ annee }}</h4>
      <div class="field"><label>COLLABORATEUR</label>
        <select v-model="forme.salarie_id">
          <option :value="null">—</option>
          <option v-for="c in collaborateurs" :key="c.id" :value="c.id">{{ c.matricule }} — {{ c.nom }}</option>
        </select></div>
      <div class="field"><label>POINTS FORTS</label>
        <textarea v-model="forme.points_forts" rows="3" placeholder="Ce qui a bien fonctionné ce trimestre…"></textarea></div>
      <div class="field"><label>AXES D'AMÉLIORATION</label>
        <textarea v-model="forme.axes_amelioration" rows="3" placeholder="Points de progrès, actions convenues…"></textarea></div>
      <div style="display:flex; gap:8px; margin-top:14px; justify-content:flex-end">
        <button class="btn ghost" @click="modale = false">ANNULER</button>
        <button class="btn" @click="enregistrer">ENREGISTRER</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
h3 { font-size: 13px; color: var(--color-brand-dark); margin-bottom: 8px; }
.forme { display: flex; gap: 10px; background: var(--color-surface); padding: 14px; border-radius: var(--radius-md); margin-bottom: 12px; flex-wrap: wrap; }
.field { min-width: 200px; }
.overlay { position: fixed; inset: 0; background: rgba(15, 23, 42, .45); z-index: 900; }
.modale { position: fixed; z-index: 901; top: 50%; left: 50%; transform: translate(-50%, -50%); background: var(--color-surface); border-radius: var(--radius-lg); box-shadow: var(--shadow-card); padding: 20px; width: min(560px, 94vw); }
textarea { width: 100%; }
</style>
