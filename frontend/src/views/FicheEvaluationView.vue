<!-- 2026-10-03 PATCH3 — M4 réécrite : date à côté du N°, critères numérotés
     dès 1, onglets à gauche, clic SIMPLE -> QCM, barre d'icônes en haut à
     droite (sauvegarde / cadenas / impression) avec hints, colonnes triables,
     vraies modales (plus de confirm()/prompt()), colonnes N visibles en
     lecture par le N+1, impression = en-tête + TOUS les onglets. -->
<script setup>
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { Lock, Save, Printer, Check, X } from 'lucide-vue-next'
import api from '../api/client'
import DataTable from '../components/DataTable.vue'
import { useConfirm } from '../composables/useConfirm'

const { confirm } = useConfirm()
const route = useRoute()
const router = useRouter()
const fiche = ref(null)
const erreur = ref('')
const message = ref('')
const onglet = ref(null)
const qcm = ref(null)          // { ligne, etape }
const reponse = ref({ detailId: null, commentaire: '' })
const clotureEnCours = ref(false)
const impression = ref(false)  // mode impression : tous les onglets
const modaleApprob = ref(null) // { decision } pour l'observation N+2
const observation = ref('')

async function charger() {
  fiche.value = (await api.get('/evaluations/' + route.params.evaluationId)).data
  if (!onglet.value) onglet.value = fiche.value.profils[0]?.profil_id || null
}
onMounted(async () => {
  try { await charger() } catch (e) { erreur.value = e.response?.data?.detail || 'Accès refusé.' }
})

const profils = computed(() => {
  const map = new Map()
  for (const l of fiche.value?.profils || []) {
    if (!map.has(l.profil_id)) map.set(l.profil_id, { id: l.profil_id, libelle: l.profil_libelle, lignes: [] })
    map.get(l.profil_id).lignes.push(l)
  }
  for (const p of map.values()) p.lignes = p.lignes.map((l, i) => ({ ...l, numero: i + 1 }))
  return [...map.values()]
})
const lignesOnglet = computed(() => profils.value.find(p => p.id === onglet.value)?.lignes || [])

const etapeCourante = computed(() => fiche.value?.mon_etape === 'N' ? 'N' : 'N+1')
const peutSaisirN = computed(() => fiche.value?.mon_etape === 'N' && fiche.value.entete.statut_n === 'En cours')
const peutSaisirN1 = computed(() => fiche.value?.mon_etape === 'N+1' && fiche.value.entete.statut_n1 === 'En cours')
const peutCloturer = computed(() => peutSaisirN.value || peutSaisirN1.value)
const peutApprouver = computed(() => fiche.value?.mon_etape === 'N+2' && fiche.value.entete.statut_n1 === 'Clôturée' && fiche.value.entete.statut_global !== 'Approuvé')

/* --- clic simple sur la cellule de SON étape -> QCM --- */
function surClic(ligne, etape) {
  if ((etape === 'N' && !peutSaisirN.value) || (etape === 'N+1' && !peutSaisirN1.value)) return
  qcm.value = { ligne, etape }
  reponse.value = { detailId: null, commentaire: '' }
}

async function validerQcm() {
  if (!reponse.value.detailId || !reponse.value.commentaire.trim()) {
    erreur.value = "Cochez une description ET saisissez un commentaire (obligatoire pour l'objectivité du jugement)."
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
    await charger()
    message.value = 'Saisie enregistrée.'
  } catch (e) { erreur.value = e.response?.data?.detail }
}

/* --- icône sauvegarde : s'assure que tout est persisté (rafraîchit) --- */
async function sauvegarder() {
  message.value = ''
  try {
    await charger()
    message.value = 'Vos saisies en cours sont enregistrées.'
  } catch (e) { erreur.value = e.response?.data?.detail }
}

/* --- cadenas : vraie modale de confirmation --- */
async function cloturer() {
  const etape = etapeCourante.value
  const libelle = etape === 'N' ? 'mon auto-évaluation' : 'mon évaluation N+1'
  const ok = await confirm({
    title: 'Clôturer ' + libelle,
    message: 'Clôturer définitivement cette étape ? Action irréversible (seul l\'Admin peut déverrouiller, avec justification).',
    danger: true, confirmLabel: 'Clôturer',
  })
  if (!ok) return
  clotureEnCours.value = true
  message.value = ''
  try {
    await api.post('/evaluations/' + route.params.evaluationId + '/cloturer', { etape })
    await charger()
    message.value = 'Étape clôturée.'
  } catch (e) { erreur.value = e.response?.data?.detail } finally { clotureEnCours.value = false }
}

/* --- impression : en-tête + TOUS les onglets --- */
async function imprimer() {
  impression.value = true
  await new Promise(r => setTimeout(r, 150))   // laisser le DOM se construire
  window.print()
  impression.value = false
}

/* --- approbation N+2 : modale (plus de prompt) --- */
function ouvrirApprobation(decision) { modaleApprob.value = { decision }; observation.value = '' }
async function approuver() {
  const decision = modaleApprob.value.decision
  const obs = decision === 'Approuvé avec réserves' ? observation.value.trim() : null
  if (decision === 'Approuvé avec réserves' && !obs) {
    erreur.value = 'Observation obligatoire pour une approbation avec réserves.'
    return
  }
  try {
    await api.post('/evaluations/' + route.params.evaluationId + '/approuver', { decision, observation: obs })
    router.push('/notations/' + route.params.evaluationId)
  } catch (e) { erreur.value = e.response?.data?.detail }
}

const COLONNES = [
  { key: 'numero', label: 'N°', align: 'center', searchable: false },
  { key: 'critere_libelle', label: 'Critère' },
  { key: 'auto_libelle', label: 'Auto-évaluation' },
  { key: 'commentaire_n', label: 'Commentaire N' },
  { key: 'eval_libelle', label: 'Évaluation N+1' },
  { key: 'commentaire_n1', label: 'Commentaire N+1' },
]
</script>

<template>
  <div v-if="fiche" class="fiche">
    <!-- En-tête : N° + DATE sur la même ligne -->
    <div class="entete">
      <div class="entete-ligne-principale">
        <span><b>N° ÉVALUATION</b> {{ fiche.entete.numero }}</span>
        <span class="sep"></span>
        <span><b>DATE</b> {{ fiche.entete.date_evaluation || '—' }}</span>
      </div>
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

    <!-- Onglets profils (gauche) + barre d'icônes (droite, même alignement) -->
    <div class="barre-onglets">
      <div class="tabs gauche">
        <button v-for="p in profils" :key="p.id" class="tab" :class="{ active: p.id === onglet }"
          :title="'Profil : ' + p.libelle" @click="onglet = p.id">{{ p.libelle }}</button>
      </div>
      <div class="icones">
        <button v-if="peutSaisirN || peutSaisirN1" class="icon-btn"
          title="Valider mes saisies en cours (chaque réponse est enregistrée immédiatement)"
          @click="sauvegarder"><Save :size="16" /></button>
        <button v-if="peutCloturer" class="icon-btn danger"
          title="Clôturer mon étape (cadenas définitif, contrôles de complétude appliqués)"
          :disabled="clotureEnCours" @click="cloturer"><Lock :size="16" /></button>
        <button class="icon-btn"
          title="Imprimer ma fiche complète (en-tête + tous les onglets), telle que présentée à l'écran"
          @click="imprimer"><Printer :size="16" /></button>
      </div>
    </div>

    <!-- Grille triable -->
    <DataTable :columns="COLONNES" :rows="lignesOnglet" :row-key="'critere_id'"
      search-placeholder="Rechercher un critère…">
      <template #cell-auto_libelle="{ row }">
        <span v-if="peutSaisirN" class="cell-saisie"
          title="Cliquer pour choisir la description qui vous décrit le mieux"
          @click="surClic(row, 'N')">{{ row.auto_libelle || '— cliquer —' }}</span>
        <span v-else class="lecture">{{ row.auto_libelle || '' }}</span>
      </template>
      <template #cell-commentaire_n="{ row }">
        <span v-if="peutSaisirN" class="cell-saisie"
          title="Saisi avec la description lors du QCM" @click="surClic(row, 'N')">{{ row.commentaire_n || '—' }}</span>
        <span v-else class="lecture">{{ row.commentaire_n }}</span>
      </template>
      <template #cell-eval_libelle="{ row }">
        <span v-if="peutSaisirN1" class="cell-saisie"
          title="Cliquer pour choisir la description qui décrit le mieux le salarié"
          @click="surClic(row, 'N+1')">{{ row.eval_libelle || '— cliquer —' }}</span>
        <span v-else class="lecture">{{ row.eval_libelle }}</span>
      </template>
      <template #cell-commentaire_n1="{ row }">
        <span v-if="peutSaisirN1" class="cell-saisie"
          title="Saisi avec la description lors du QCM (différent du commentaire du salarié)"
          @click="surClic(row, 'N+1')">{{ row.commentaire_n1 || '—' }}</span>
        <span v-else class="lecture">{{ row.commentaire_n1 }}</span>
      </template>
    </DataTable>

    <!-- Approbation N+2 -->
    <div v-if="peutApprouver" style="margin-top:16px;display:flex;gap:8px">
      <button class="btn" title="Approuver la fiche sans réserve (définitif)" @click="ouvrirApprobation('Approuvé')">APPROUVER</button>
      <button class="btn ghost" title="Approuver avec réserves : observation obligatoire" @click="ouvrirApprobation('Approuvé avec réserves')">APPROUVER AVEC RESERVES</button>
    </div>
    <div v-if="fiche.entete.statut_n1 === 'Clôturée'" style="margin-top:16px">
      <button class="btn ghost" title="Voir le détail des notations et le score" @click="router.push('/notations/' + route.params.evaluationId)">VOIR NOTATIONS</button>
    </div>

    <!-- Modale QCM (premium) -->
    <div v-if="qcm" class="modal-bg" @click.self="qcm = null">
      <div class="modal qcm-modal">
        <div class="qcm-entete">
          <h3 class="qcm-titre">{{ qcm.ligne.critere_libelle }}</h3>
          <button class="icon-btn" title="Fermer sans enregistrer (Échap)" @click="qcm = null">
            <X :size="16" /></button>
        </div>
        <p class="qcm-consigne">Cochez la description qui correspond le mieux à vos aptitudes.
           Il n'y a pas de bonne ou mauvaise réponse.</p>

        <div class="qcm-options">
          <label v-for="(d, i) in qcm.ligne.details" :key="d.id"
            class="qcm-option" :class="{ choisi: reponse.detailId === d.id }"
            :title="'Choisir : ' + d.libelle">
            <input type="radio" name="qcm" :value="d.id" v-model="reponse.detailId" class="qcm-radio" />
            <span class="qcm-numero">{{ i + 1 }}</span>
            <span class="qcm-libelle">{{ d.libelle }}</span>
            <Check v-if="reponse.detailId === d.id" :size="16" class="qcm-check" />
          </label>
        </div>

        <div class="qcm-commentaire">
          <label>COMMENTAIRE — OBLIGATOIRE</label>
          <textarea rows="3" v-model="reponse.commentaire" placeholder="Justifiez votre choix…"
            title="Obligatoire pour l'objectivité du jugement"></textarea>
        </div>

        <div class="qcm-actions">
          <button class="btn ghost" title="Fermer sans enregistrer" @click="qcm = null">Annuler</button>
          <button class="btn" :disabled="!reponse.detailId || !reponse.commentaire.trim()"
            title="Enregistrer la description et le commentaire" @click="validerQcm">Valider</button>
        </div>
      </div>
    </div>

    <!-- Modale observation N+2 -->
    <div v-if="modaleApprob" class="modal-bg" @click.self="modaleApprob = null">
      <div class="modal" style="max-width:520px">
        <h3>APPROUVER AVEC RESERVES</h3>
        <div class="field"><label>OBSERVATION (OBLIGATOIRE)</label>
          <textarea rows="3" v-model="observation"
            title="Précisez les réserves qui motivent cette décision"></textarea></div>
        <div style="display:flex;gap:8px;justify-content:flex-end">
          <button class="btn ghost" title="Annuler l'approbation" @click="modaleApprob = null">Annuler</button>
          <button class="btn" title="Enregistrer l'approbation avec réserves" @click="approuver">Confirmer</button>
        </div>
      </div>
    </div>

    <!-- VERSION IMPRESSION : en-tête + TOUS les onglets -->
    <div v-if="impression" class="zone-impression">
      <div class="entete">
        <div class="entete-ligne-principale">
          <span><b>N° ÉVALUATION</b> {{ fiche.entete.numero }}</span>
          <span class="sep"></span>
          <span><b>DATE</b> {{ fiche.entete.date_evaluation || '—' }}</span>
        </div>
        <div><b>MATRICULE</b> {{ fiche.entete.matricule }} — <b>NOM</b> {{ fiche.entete.nom }}</div>
        <div><b>EMPLOI</b> {{ fiche.entete.emploi || '—' }} · <b>POSTE</b> {{ fiche.entete.poste || '—' }} · <b>CATEGORIE</b> {{ fiche.entete.categorie || '—' }}</div>
        <div><b>DEPARTEMENT</b> {{ fiche.entete.departement || '—' }} · <b>SECTION</b> {{ fiche.entete.section || '—' }} · <b>N+1</b> {{ fiche.entete.n1_nom || '—' }}</div>
      </div>
      <div v-for="p in profils" :key="p.id">
        <h4 class="titre-profil-impression">{{ p.libelle }}</h4>
        <table class="data">
          <thead><tr><th>N°</th><th>CRITERE</th><th>AUTO-EVALUATION</th><th>COMMENTAIRE N</th>
            <th>EVALUATION N+1</th><th>COMMENTAIRE N+1</th></tr></thead>
          <tbody>
            <tr v-for="l in p.lignes" :key="l.critere_id">
              <td>{{ l.numero }}</td><td>{{ l.critere_libelle }}</td>
              <td>{{ l.auto_libelle }}</td><td>{{ l.commentaire_n }}</td>
              <td>{{ l.eval_libelle }}</td><td>{{ l.commentaire_n1 }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
  <div v-else class="error">{{ erreur }}</div>
</template>

<style scoped>
.fiche { max-width: 1200px; }
.entete { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 14px; font-size: 13px; display: grid; gap: 4px; margin-bottom: 12px; }
.entete-ligne-principale { display: flex; align-items: center; }
.sep { flex: 0 0 24px; }
b { color: var(--color-brand-dark); font-size: 11px; margin-right: 6px; }
.barre-onglets { display: flex; align-items: stretch; justify-content: space-between; gap: var(--space-4); }
.tabs.gauche { justify-content: flex-start; flex: 1; }
.icones { display: flex; align-items: center; gap: var(--space-2); padding-bottom: var(--space-3); }
.cell-saisie { cursor: pointer; display: block; padding: 4px 8px; margin: -4px -8px; border-radius: 6px; }
.cell-saisie:hover { background: var(--color-brand-light); }
.lecture { color: var(--color-text); }
/* Impression : uniquement la zone d'impression, sans navigation */
.zone-impression { display: none; }
@media print {
  .fiche > *:not(.zone-impression) { display: none !important; }
  .zone-impression { display: block !important; }
  .titre-profil-impression { margin: 18px 0 6px; color: var(--color-brand-dark); }
}

/* ---------- Modale QCM premium ---------- */
.qcm-modal { max-width: 560px; padding: var(--space-6); }
.qcm-entete { display: flex; align-items: flex-start; justify-content: space-between; gap: var(--space-3); margin-bottom: var(--space-2); }
.qcm-titre { margin: 0; font-size: var(--font-size-lg); color: var(--color-brand-dark); font-weight: 800; }
.qcm-consigne { margin: 0 0 var(--space-6); color: var(--color-text-muted); font-size: var(--font-size-sm); line-height: 1.5; }
.qcm-options { display: flex; flex-direction: column; gap: var(--space-2); margin-bottom: var(--space-6); }
.qcm-option {
  display: flex; align-items: center; gap: var(--space-3);
  border: 1px solid var(--color-border); border-radius: var(--radius-md);
  padding: var(--space-3) var(--space-4); cursor: pointer;
  background: var(--color-surface); transition: border-color .15s ease, background-color .15s ease, transform .15s ease;
}
.qcm-option:hover { border-color: var(--color-brand); background: var(--color-brand-light); transform: translateY(-1px); }
.qcm-option.choisi { border-color: var(--color-brand); background: var(--color-brand-light); box-shadow: 0 0 0 1px var(--color-brand); }
.qcm-radio { position: absolute; opacity: 0; pointer-events: none; width: 0; }
.qcm-numero {
  flex-shrink: 0; width: 26px; height: 26px; border-radius: 50%;
  background: var(--color-bg); color: var(--color-text-muted);
  display: flex; align-items: center; justify-content: center;
  font-size: var(--font-size-xs); font-weight: 800;
}
.qcm-option.choisi .qcm-numero { background: var(--color-brand); color: var(--color-text-inverse); }
.qcm-libelle { flex: 1; font-size: var(--font-size-sm); line-height: 1.4; }
.qcm-check { color: var(--color-brand); flex-shrink: 0; }
.qcm-commentaire label { font-size: var(--font-size-xs); font-weight: 800; letter-spacing: .5px; margin-bottom: var(--space-1); }
.qcm-actions { display: flex; justify-content: flex-end; gap: var(--space-2); margin-top: var(--space-6); }
</style>
