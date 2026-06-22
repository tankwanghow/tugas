const modalKey = id => `argus:completion-modal:${id}`
const stepKey = id => `argus:step-files:${id}`
const errorKey = id => `argus:upload-error:${id}`

// A slot error can be raised while the socket is down (the size check runs when
// the camera returns mid-reconnect). Stash it so restore() can re-show it once
// the modal is rendered again — displayed purely client-side (no server event).
export function persistUploadError(obligationId, idPrefix, slot, message) {
  if (!obligationId) return
  try {
    sessionStorage.setItem(errorKey(obligationId), JSON.stringify({idPrefix, slot, message}))
  } catch (_e) {
    // ignore quota/serialisation errors
  }
}

export function clearUploadError(obligationId) {
  if (!obligationId) return
  sessionStorage.removeItem(errorKey(obligationId))
}

export function clearUploadPersist(obligationId) {
  if (!obligationId) return

  sessionStorage.removeItem(modalKey(obligationId))
  sessionStorage.removeItem(stepKey(obligationId))
  sessionStorage.removeItem(errorKey(obligationId))
}

export function showClientSlotError(idPrefix, slot, message) {
  const controls = document.querySelector(`[data-upload-slot-controls="${idPrefix}${slot}"]`)
  if (!controls) return

  const errorEl = controls.querySelector("[data-client-upload-error]")
  const errorRow = controls.querySelector("[data-client-upload-error-row]")
  const actionsEl = controls.querySelector("[data-upload-slot-actions]")

  if (errorEl) errorEl.textContent = message
  if (errorRow) errorRow.classList.remove("hidden")
  if (actionsEl) actionsEl.classList.add("hidden")
}

export function clearClientSlotError(idPrefix, slot) {
  const controls = document.querySelector(`[data-upload-slot-controls="${idPrefix}${slot}"]`)
  if (!controls) return

  const errorEl = controls.querySelector("[data-client-upload-error]")
  const errorRow = controls.querySelector("[data-client-upload-error-row]")
  const actionsEl = controls.querySelector("[data-upload-slot-actions]")

  if (errorEl) errorEl.textContent = ""
  if (errorRow) errorRow.classList.add("hidden")
  if (actionsEl) actionsEl.classList.remove("hidden")
}

export const UploadUiPersist = {
  mounted() {
    this.obligationId = this.el.dataset.obligationId

    this.handleEvent("persist_completion_modal", () => {
      if (!this.obligationId) return
      sessionStorage.setItem(modalKey(this.obligationId), "1")
      sessionStorage.removeItem(stepKey(this.obligationId))
    })

    this.handleEvent("clear_completion_modal_persist", () => {
      clearUploadPersist(this.obligationId)
    })

    this.handleEvent("persist_step_files", ({event_id}) => {
      if (!this.obligationId || !event_id) return
      sessionStorage.setItem(stepKey(this.obligationId), event_id)
      sessionStorage.removeItem(modalKey(this.obligationId))
    })

    this.handleEvent("clear_step_files_persist", () => {
      if (this.obligationId) sessionStorage.removeItem(stepKey(this.obligationId))
    })

    this.restore()
  },

  reconnected() {
    this.restore()
  },

  restore() {
    if (!this.obligationId) return

    const modalFlag = sessionStorage.getItem(modalKey(this.obligationId))
    const stepFlag = sessionStorage.getItem(stepKey(this.obligationId))

    let pendingError = null
    const errorRaw = sessionStorage.getItem(errorKey(this.obligationId))
    if (errorRaw) {
      sessionStorage.removeItem(errorKey(this.obligationId))
      try {
        pendingError = JSON.parse(errorRaw)
      } catch (_e) {
        pendingError = null
      }
    }

    // Re-show the stashed slot error once the restored modal has been patched in.
    const showErr = () => {
      if (!pendingError) return
      requestAnimationFrame(() =>
        showClientSlotError(pendingError.idPrefix, pendingError.slot, pendingError.message)
      )
    }

    if (modalFlag === "1") {
      this.pushEvent("restore_completion_modal", {}, showErr)
    } else if (stepFlag) {
      this.pushEvent("restore_step_files", {event_id: stepFlag}, showErr)
    } else {
      showErr()
    }
  },
}