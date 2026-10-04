/**
 * useConfirm.js -- remplace window.confirm() par une vraie modale applicative
 * (cf. ConfirmDialog.vue, monté une seule fois dans App.vue). Copie du pattern
 * vusine : état module-level, une seule modale à la fois dans toute l'appli.
 *
 * Usage :
 *   const { confirm } = useConfirm()
 *   if (!(await confirm({ title: 'Supprimer', message: `Supprimer ${nom} ?`,
 *                         danger: true, confirmLabel: 'Supprimer' }))) return
 */
import { reactive } from 'vue'

const state = reactive({
  visible: false, title: '', message: '',
  danger: false, confirmLabel: 'Confirmer', cancelLabel: 'Annuler', resolve: null,
})

export function useConfirm() {
  function confirm({ title = 'Confirmer', message = '', danger = false,
                     confirmLabel = 'Confirmer', cancelLabel = 'Annuler' } = {}) {
    return new Promise((resolve) => {
      if (state.resolve) state.resolve(false)
      Object.assign(state, { visible: true, title, message, danger, confirmLabel, cancelLabel, resolve })
    })
  }
  return { state, confirm }
}

export function _repondreConfirm(valeur) {
  state.visible = false
  const r = state.resolve
  state.resolve = null
  if (r) r(valeur)
}

export function _confirmState() { return state }
