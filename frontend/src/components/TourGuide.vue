<!-- PATCH 10 — onboarding guidé : visite en 6 étapes à la 1re connexion,
     relançable depuis MON ESPACE (localStorage 'tourFait'). -->
<script setup>
import { ref } from 'vue'
import { X, ChevronLeft, ChevronRight } from 'lucide-vue-next'

const ETAPES = [
  { titre: 'Bienvenue sur EVALPOINT', texte: "La plateforme d'évaluation du personnel SIVOP. Cette visite rapide vous présente les écrans essentiels (30 secondes)." },
  { titre: 'MON ESPACE', texte: 'Votre page d\'accueil : rôle (N, N+1, N+2), fiches à traiter, notifications et raccourcis.' },
  { titre: 'EVALUATIONS', texte: 'La campagne active et la liste des fiches de votre périmètre : filtrer par section, ouvrir une fiche.' },
  { titre: 'Votre fiche (QCM)', texte: "Cliquez une cellule de votre étape : cochez la description qui vous décrit le mieux, ajoutez un commentaire (obligatoire). Chaque réponse est enregistrée immédiatement — une barre d'avancement vous suit." },
  { titre: 'Cadenas & signatures', texte: "Clôturez votre étape (cadenas, irréversible), puis signez électroniquement : badge SIGNÉ horodaté avec empreinte SHA-256." },
  { titre: 'Check-ins & objectifs', texte: 'Entre les campagnes : check-ins trimestriels et objectifs OKR avec vos collaborateurs (menus CHECK-INS / OBJECTIFS).' },
]
const visible = ref(!localStorage.getItem('tourFait') && !!localStorage.getItem('token'))
const etape = ref(0)

function suivant() { etape.value < ETAPES.length - 1 ? etape.value++ : terminer() }
function precedent() { if (etape.value > 0) etape.value-- }
function terminer() { localStorage.setItem('tourFait', '1'); visible.value = false }
</script>

<template>
  <div v-if="visible" class="tour-overlay">
    <div class="tour-box">
      <button class="tour-x" title="Fermer la visite" @click="terminer"><X :size="18" /></button>
      <div class="tour-num">{{ etape + 1 }} / {{ ETAPES.length }}</div>
      <h4>{{ ETAPES[etape].titre }}</h4>
      <p>{{ ETAPES[etape].texte }}</p>
      <div class="tour-actions">
        <button v-if="etape > 0" class="vbtn ghost" @click="precedent"><ChevronLeft :size="14" /> PRÉCÉDENT</button>
        <span style="flex:1"></span>
        <button class="vbtn ghost" @click="terminer">PASSER</button>
        <button class="vbtn" @click="suivant">
          {{ etape === ETAPES.length - 1 ? 'TERMINER' : 'SUIVANT' }} <ChevronRight :size="14" />
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.tour-overlay { position: fixed; inset: 0; background: rgba(15, 23, 42, .55); z-index: 1200; display: flex; align-items: center; justify-content: center; padding: 16px; }
.tour-box { position: relative; background: var(--color-surface); border-radius: var(--radius-lg); box-shadow: var(--shadow-card); max-width: 480px; width: 100%; padding: 22px; }
.tour-x { position: absolute; top: 10px; right: 10px; background: none; border: none; cursor: pointer; color: var(--color-text-muted); }
.tour-num { font-size: 11px; font-weight: 700; color: var(--color-brand); }
h4 { margin: 4px 0 8px; font-size: 15px; color: var(--color-brand-dark); }
p { font-size: 13px; color: var(--color-text); line-height: 1.5; }
.tour-actions { display: flex; gap: 8px; margin-top: 16px; align-items: center; }
</style>
