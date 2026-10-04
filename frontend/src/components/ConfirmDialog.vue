<!-- ConfirmDialog.vue — monté UNE SEULE FOIS dans App.vue. Toute la vue peut
     déclencher la modale via useConfirm(). Escape = Annuler, Entrée = Confirmer,
     focus sur Annuler par défaut (action destructrice jamais déclenchée par
     une pression Entrée trop rapide). -->
<script setup>
import { onMounted, onUnmounted, nextTick, ref, watch } from 'vue'
import { _confirmState, _repondreConfirm } from '../composables/useConfirm'

const state = _confirmState()
const boutonAnnuler = ref(null)

function onKeydown(e) {
  if (!state.visible) return
  if (e.key === 'Escape') _repondreConfirm(false)
  if (e.key === 'Enter') _repondreConfirm(true)
}
watch(() => state.visible, async (visible) => {
  if (visible) { await nextTick(); boutonAnnuler.value?.focus() }
})
onMounted(() => window.addEventListener('keydown', onKeydown))
onUnmounted(() => window.removeEventListener('keydown', onKeydown))
</script>

<template>
  <Teleport to="body">
    <div v-if="state.visible" class="confirm-overlay" @click.self="_repondreConfirm(false)">
      <div class="confirm-box" role="alertdialog" aria-modal="true" :aria-label="state.title">
        <h2 class="confirm-title">{{ state.title }}</h2>
        <p class="confirm-message">{{ state.message }}</p>
        <div class="confirm-actions">
          <button ref="boutonAnnuler" type="button" class="vbtn vbtn-secondary"
            title="Annuler et fermer cette fenêtre (Échap)" @click="_repondreConfirm(false)">
            {{ state.cancelLabel }}
          </button>
          <button type="button" :class="['vbtn', state.danger ? 'vbtn-danger' : 'vbtn-primary']"
            :title="state.confirmLabel" @click="_repondreConfirm(true)">
            {{ state.confirmLabel }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.confirm-overlay {
  position: fixed; inset: 0; background: rgba(15, 23, 42, 0.45);
  display: flex; align-items: center; justify-content: center;
  z-index: 1000; padding: var(--space-4); animation: confirm-fade-in 0.15s ease;
}
.confirm-box {
  background: var(--color-surface); border-radius: var(--radius-lg);
  box-shadow: 0 12px 32px rgba(15, 23, 42, 0.25);
  padding: var(--space-6); width: 100%; max-width: 420px;
  animation: confirm-pop-in 0.15s ease;
}
.confirm-title { margin: 0 0 var(--space-2); font-size: var(--font-size-lg); color: var(--color-text); }
.confirm-message { margin: 0 0 var(--space-6); color: var(--color-text-muted); font-size: var(--font-size-sm); line-height: 1.5; }
.confirm-actions { display: flex; justify-content: flex-end; gap: var(--space-3); }
@keyframes confirm-fade-in { from { opacity: 0; } to { opacity: 1; } }
@keyframes confirm-pop-in { from { opacity: 0; transform: scale(0.96) translateY(4px); } to { opacity: 1; transform: scale(1) translateY(0); } }
@media (prefers-reduced-motion: reduce) { .confirm-overlay, .confirm-box { animation: none; } }
</style>
