<!-- PATCH 10 — objectifs OKR : objectifs trimestriels + résultats clés avec
     barre d'avancement, création et clôture. Mobile : cartes. -->
<script setup>
import { onMounted, ref } from 'vue'
import { Plus, Lock, Minus, PlusCircle } from 'lucide-vue-next'
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
const forme = ref({ salarie_id: null, titre: '', description: '' })
const krNouveau = ref({})   // { [objectifId]: libellé }

async function charger() {
  erreur.value = ''
  try {
    const [l, c] = await Promise.all([
      api.get('/objectifs', { params: { trimestre: trimestre.value, annee: annee.value } }),
      api.get('/checkins/collaborateurs'),
    ])
    liste.value = l.data
    collaborateurs.value = c.data
  } catch (e) { erreur.value = e.response?.data?.detail || 'Chargement impossible.' }
}
onMounted(charger)

function ouvrir() { forme.value = { salarie_id: null, titre: '', description: '' }; modale.value = true }

async function enregistrer() {
  if (!forme.value.salarie_id || !forme.value.titre.trim()) { erreur.value = 'Collaborateur et titre obligatoires.'; return }
  try {
    await api.post('/objectifs', { ...forme.value, trimestre: trimestre.value, annee: annee.value })
    modale.value = false; message.value = 'Objectif créé.'; await charger()
  } catch (e) { erreur.value = e.response?.data?.detail }
}

async function ajouterKr(o) {
  const lib = (krNouveau.value[o.id] || '').trim()
  if (!lib) { erreur.value = 'Libellé du résultat clé obligatoire.'; return }
  try { await api.post('/objectifs/' + o.id + '/krs', { libelle: lib }); krNouveau.value[o.id] = ''; await charger() }
  catch (e) { erreur.value = e.response?.data?.detail }
}

async function avancerKr(o, k, delta) {
  const v = Math.max(0, Math.min(100, (k.avancement || 0) + delta))
  try { await api.post('/objectifs/krs/' + k.id + '/avancement', { avancement: v }); await charger() }
  catch (e) { erreur.value = e.response?.data?.detail }
}

async function cloturer(o) {
  const ok = await confirm({
    title: 'Clôturer l\'objectif',
    message: `Clôturer « ${o.titre} » (${o.nom}) ?`,
    confirmLabel: 'Clôturer',
  })
  if (!ok) return
  try { await api.post('/objectifs/' + o.id + '/cloturer'); message.value = 'Objectif clôturé.'; await charger() }
  catch (e) { erreur.value = e.response?.data?.detail }
}

function barre(v) { return { height: '100%', width: (v || 0) + '%', background: 'var(--color-vert)', transition: 'width .3s' } }
</script>

<template>
  <div>
    <h3>OBJECTIFS OKR</h3>
    <div class="forme">
      <div class="field"><label>TRIMESTRE</label>
        <select v-model="trimestre" @change="charger">
          <option :value="1">T1</option><option :value="2">T2</option>
          <option :value="3">T3</option><option :value="4">T4</option>
        </select></div>
      <div class="field"><label>ANNÉE</label><input type="number" v-model="annee" @change="charger" /></div>
      <button class="btn" title="Fixer un nouvel objectif trimestriel" @click="ouvrir"><Plus :size="14" /> NOUVEL OBJECTIF</button>
    </div>
    <div v-if="message" class="ok">{{ message }}</div>
    <div v-if="erreur" class="error">{{ erreur }}</div>

    <div v-for="o in liste" :key="o.id" class="card obj">
      <div class="obj-titre">
        <b>{{ o.titre }}</b>
        <span class="muted">{{ o.matricule }} — {{ o.nom }} · T{{ o.trimestre }} {{ o.annee }}</span>
        <span class="badge-statut" :class="o.statut === 'Clôturé' ? 'statut-vert' : 'statut-orange'">{{ o.statut }}</span>
        <button v-if="o.statut !== 'Clôturé'" class="icon-btn" style="margin-left:auto; color: var(--color-vert)"
          title="Clôturer cet objectif" @click="cloturer(o)"><Lock :size="15" /></button>
      </div>
      <div v-if="o.description" class="muted" style="margin: 4px 0 8px;">{{ o.description }}</div>
      <div v-for="k in o.krs" :key="k.id" class="kr">
        <span class="kr-lib">{{ k.libelle }}</span>
        <div class="kr-barre"><div :style="barre(k.avancement)"></div></div>
        <span class="kr-pct">{{ k.avancement }} %</span>
        <template v-if="o.statut !== 'Clôturé'">
          <button class="icon-btn" title="Reculer de 10 %" @click="avancerKr(o, k, -10)"><Minus :size="14" /></button>
          <button class="icon-btn" title="Avancer de 10 %" @click="avancerKr(o, k, 10)"><PlusCircle :size="14" /></button>
        </template>
      </div>
      <div v-if="o.statut !== 'Clôturé'" class="kr-ajout">
        <input v-model="krNouveau[o.id]" placeholder="Nouveau résultat clé…" />
        <button class="btn ghost" title="Ajouter ce résultat clé" @click="ajouterKr(o)">AJOUTER</button>
      </div>
      <div v-if="!o.krs.length && o.statut === 'Clôturé'" class="muted">Aucun résultat clé.</div>
    </div>
    <div v-if="!liste.length" class="muted">Aucun objectif ce trimestre.</div>

    <div v-if="modale" class="overlay" @click.self="modale = false"></div>
    <div v-if="modale" class="modale">
      <h4>NOUVEL OBJECTIF — T{{ trimestre }} {{ annee }}</h4>
      <div class="field"><label>COLLABORATEUR</label>
        <select v-model="forme.salarie_id">
          <option :value="null">—</option>
          <option v-for="c in collaborateurs" :key="c.id" :value="c.id">{{ c.matricule }} — {{ c.nom }}</option>
        </select></div>
      <div class="field"><label>TITRE</label><input v-model="forme.titre" placeholder="Ex. Réduire les délais de livraison" /></div>
      <div class="field"><label>DESCRIPTION</label><textarea v-model="forme.description" rows="3" placeholder="Contexte, attendus…"></textarea></div>
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
.card.obj { background: var(--color-surface); border-radius: var(--radius-md); padding: 14px; margin-bottom: 10px; box-shadow: var(--shadow-card); }
.obj-titre { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
.muted { color: var(--color-text-muted); font-size: 12px; }
.kr { display: flex; gap: 8px; align-items: center; margin-top: 8px; flex-wrap: wrap; }
.kr-lib { min-width: 180px; font-size: 13px; }
.kr-barre { flex: 1; min-width: 120px; height: 8px; background: var(--color-border); border-radius: 4px; overflow: hidden; }
.kr-pct { font-size: 12px; font-weight: 700; min-width: 44px; text-align: right; }
.kr-ajout { display: flex; gap: 8px; margin-top: 10px; }
.kr-ajout input { flex: 1; }
.overlay { position: fixed; inset: 0; background: rgba(15, 23, 42, .45); z-index: 900; }
.modale { position: fixed; z-index: 901; top: 50%; left: 50%; transform: translate(-50%, -50%); background: var(--color-surface); border-radius: var(--radius-lg); box-shadow: var(--shadow-card); padding: 20px; width: min(560px, 94vw); }
</style>
