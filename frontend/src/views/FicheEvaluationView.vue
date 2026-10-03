<!-- 2026-10-02 — M4 : écran pivot. Onglets = profils de l'emploi ; grille
     N°/CRITERE/AUTO-EVALUATION/COMMENTAIRE N/EVALUATION N+1/COMMENTAIRE N+1 ;
     double-clic -> QCM choix unique (« pas de bonne ou mauvaise réponse ») ;
     commentaire obligatoire ; cadenas en bas de fiche. -->
<script setup>
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { Lock } from 'lucide-vue-next'
import api from '../api/client'

const route = useRoute()
const router = useRouter()
const fiche = ref(null)
const erreur = ref('')
const message = ref('')
const onglet = ref(null)
const qcm = ref(null)   // { ligne, etape }
const reponse = ref({ detailId: null, commentaire: '' })
const clotureEnCours = ref(false)

onMounted(async () => {
  try {
    fiche.value = (await api.get('/evaluations/' + route.params.evaluationId)).data
    onglet.value = fiche.value.profils[0]?.profil_id || null
  } catch (e) { erreur.value = e.response?.data?.detail || 'Accès refusé.' }
})

const profils = computed(() => {
  const map = new Map()
  for (const l of fiche.value?.profils || []) {
    if (!map.has(l.profil_id)) map.set(l.profil_id, { id: l.profil_id, libelle: l.profil_libelle, lignes: [] })
    map.get(l.profil_id).lignes.push(l)
  }
  return [...map.values()]
})
const lignesOnglet = computed(() => profils.value.find(p => p.id === onglet.value)?.lignes || [])

const peutSaisirN = computed(() => fiche.value?.mon_etape === 'N' && fiche.value.entete.statut_n === 'En cours')
const peutSaisirN1 = computed(() => fiche.value?.mon_etape === 'N+1' && fiche.value.entete.statut_n1 === 'En cours')
const peutApprouver = computed(() => fiche.value?.mon_etape === 'N+2' && fiche.value.entete.statut_n1 === 'Clôturée' && fiche.value.entete.statut_global !== 'Approuvé')

function ouvrirQcm(ligne, etape) {
  if ((etape === 'N' && !peutSaisirN.value) || (etape === 'N+1' && !peutSaisirN1.value)) return
  qcm.value = { ligne, etape }
  reponse.value = { detailId: null, commentaire: '' }
}

async function validerQcm() {
  if (!reponse.value.detailId || !reponse.value.commentaire.trim()) {
    erreur.value = 'Cochez une description ET saisissez un commentaire (obligatoire pour l\'objectivité du jugement).'
    return
  }
  try {
    await api.post('/evaluations/' + route.params.evaluationId + '/qcm', {
      etape: qcm.value.etape, profil_id: qcm.value.ligne.profil_id,
      critere_id: qcm.value.ligne.critere_id,
      critere_detail_id: reponse.value.detailId,
      commentaire: reponse.value.commentaire.trim(),
    })
    qcm.value = null
    fiche.value = (await api.get('/evaluations/' + route.params.evaluationId)).data
  } catch (e) { erreur.value = e.response?.data?.detail }
}

async function cloturer(etape) {
  if (!confirm('Clôturer définitivement cette étape ? Action irréversible (seul l\'Admin peut déverrouiller).')) return
  clotureEnCours.value = true
  message.value = ''
  try {
    await api.post('/evaluations/' + route.params.evaluationId + '/cloturer', { etape })
    fiche.value = (await api.get('/evaluations/' + route.params.evaluationId)).data
    message.value = 'Étape clôturée.'
  } catch (e) { erreur.value = e.response?.data?.detail } finally { clotureEnCours.value = false }
}

async function approuver(decision) {
  const observation = decision === 'Approuvé avec réserves' ? prompt('Observation (obligatoire) :') : null
  if (decision === 'Approuvé avec réserves' && !observation) return
  try {
    await api.post('/evaluations/' + route.params.evaluationId + '/approuver', { decision, observation })
    router.push('/notations/' + route.params.evaluationId)
  } catch (e) { erreur.value = e.response?.data?.detail }
}
</script>

<template>
  <div v-if="fiche">
    <!-- En-tête complet (§6.1) -->
    <div class="entete">
      <div><b>N° ÉVALUATION</b> {{ fiche.entete.numero }}</div>
      <div><b>MATRICULE</b> {{ fiche.entete.matricule }} — <b>NOM</b> {{ fiche.entete.nom }}</div>
      <div><b>EMPLOI</b> {{ fiche.entete.emploi || '—' }} · <b>POSTE</b> {{ fiche.entete.poste || '—' }}</div>
      <div><b>DEPARTEMENT</b> {{ fiche.entete.departement || '—' }} · <b>SECTION</b> {{ fiche.entete.section || '—' }} · <b>CATEGORIE</b> {{ fiche.entete.categorie || '—' }}</div>
      <div><b>ANCIENNETE</b> {{ fiche.entete.anciennete_annees ?? '—' }} ans · <b>N+1</b> {{ fiche.entete.n1_nom || '—' }} ({{ fiche.entete.n1_poste || '—' }})</div>
      <div>
        <span class="badge-warn">N : {{ fiche.entete.statut_n }}</span>
        <span class="badge-warn">N+1 : {{ fiche.entete.statut_n1 }}</span>
        <span class="badge-warn">N+2 : {{ fiche.entete.statut_n2 }}</span>
        <span class="badge-warn">GLOBAL : {{ fiche.entete.statut_global }}</span>
      </div>
    </div>
    <div v-if="erreur" class="error">{{ erreur }}</div>
    <div v-if="message" class="ok">{{ message }}</div>

    <!-- Onglets = profils d'évaluation de l'emploi -->
    <div class="tabs">
      <div v-for="p in profils" :key="p.id" class="tab" :class="{ active: p.id === onglet }"
           @click="onglet = p.id">{{ p.libelle }}</div>
    </div>

    <!-- Grille unique à 6 colonnes, grisage strict par rôle -->
    <table class="data">
      <thead><tr>
        <th>N°</th><th>CRITERE</th><th>AUTO-EVALUATION</th><th>COMMENTAIRE N</th>
        <th>EVALUATION N+1</th><th>COMMENTAIRE N+1</th>
      </tr></thead>
      <tbody>
        <tr v-for="l in lignesOnglet" :key="l.critere_id" @dblclick="ouvrirQcm(l, fiche.mon_etape === 'N' ? 'N' : 'N+1')"
            :style="{ cursor: (peutSaisirN || peutSaisirN1) ? 'pointer' : 'default' }">
          <td>{{ l.ordre }}</td>
          <td>{{ l.critere_libelle }}</td>
          <td :class="{ 'cell-locked': !peutSaisirN }">{{ l.auto_libelle || (peutSaisirN ? '— double-clic —' : '') }}</td>
          <td :class="{ 'cell-locked': !peutSaisirN }">{{ l.commentaire_n }}</td>
          <td :class="{ 'cell-locked': !peutSaisirN1 }">{{ l.eval_libelle || (peutSaisirN1 ? '— double-clic —' : '') }}</td>
          <td :class="{ 'cell-locked': !peutSaisirN1 }">{{ l.commentaire_n1 }}</td>
        </tr>
      </tbody>
    </table>

    <!-- Fenêtre QCM (§6.3) -->
    <div v-if="qcm" class="modal-bg">
      <div class="modal">
        <p>Veuillez cocher la description qui décrit le mieux vos aptitudes concernant ce critère.
           Nous précisons qu'il n'y a pas de bonne ou mauvaise réponse.</p>
        <p class="muted" style="margin:10px 0"><b>{{ qcm.ligne.critere_libelle }}</b></p>
        <div v-for="d in qcm.ligne.details" :key="d.id" style="margin:6px 0">
          <label style="display:flex;gap:8px;align-items:center">
            <input type="radio" name="qcm" :value="d.id" v-model="reponse.detailId" /> {{ d.libelle }}
          </label>
        </div>
        <div class="field" style="margin-top:12px">
          <label>COMMENTAIRE (OBLIGATOIRE)</label>
          <textarea rows="3" v-model="reponse.commentaire"></textarea>
        </div>
        <div style="display:flex;gap:8px;justify-content:flex-end">
          <button class="btn ghost" @click="qcm = null">Annuler</button>
          <button class="btn" @click="validerQcm">Valider</button>
        </div>
      </div>
    </div>

    <!-- Cadenas + approbation -->
    <div style="margin-top:16px;display:flex;gap:8px">
      <button v-if="peutSaisirN" class="btn danger" :disabled="clotureEnCours" @click="cloturer('N')">
        <Lock :size="14" style="vertical-align:-2px" /> CLOTURER MON AUTO-EVALUATION
      </button>
      <button v-if="peutSaisirN1" class="btn danger" :disabled="clotureEnCours" @click="cloturer('N+1')">
        <Lock :size="14" style="vertical-align:-2px" /> CLOTURER MON EVALUATION N+1
      </button>
      <button v-if="peutApprouver" class="btn" @click="approuver('Approuvé')">APPROUVER</button>
      <button v-if="peutApprouver" class="btn ghost" @click="approuver('Approuvé avec réserves')">APPROUVER AVEC RESERVES</button>
      <button v-if="fiche.entete.statut_n1 === 'Clôturée'" class="btn ghost" @click="router.push('/notations/' + route.params.evaluationId)">VOIR NOTATIONS</button>
    </div>
  </div>
  <div v-else class="error">{{ erreur }}</div>
</template>

<style scoped>
.entete { background: #fff; border-radius: 6px; padding: 14px; font-size: 13px; display: grid; gap: 4px; margin-bottom: 12px; }
b { color: #0f3b66; font-size: 11px; margin-right: 6px; }
</style>
