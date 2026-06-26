const ANIMATION_NAME = {
  created: "todo-row-created",
  updated: "todo-row-updated",
  completed: "todo-row-completed",
  deleted: "todo-row-deleted",
}

// Mobile press-and-hold: rows that carry `data-menu-id` reveal their hidden action
// menu (`[data-todo-actions-menu]`, rendered with `display:none`) after a sustained
// ~500ms press that didn't start on an interactive control. Any outside tap — or the
// LiveView re-render following an action — hides it again. Desktop rows omit
// `data-menu-id`, so the long-press branch stays inert there.
const LONG_PRESS_MS = 500
const INTERACTIVE = "input, button, a, label, select, textarea"

export const TodoRowEffect = {
  mounted() {
    this.watch()
    this.initLongPress()
  },

  updated() {
    this.watch()
  },

  destroyed() {
    this.clearListener()
    this.cancelPress()
  },

  watch() {
    const effect = this.el.dataset.effect

    if (!effect) {
      this.activeEffect = null
      this.clearListener()
      return
    }

    if (effect === this.activeEffect) return

    this.activeEffect = effect
    this.clearListener()

    const animationName = ANIMATION_NAME[effect]
    if (!animationName) return

    this.onAnimationEnd = (e) => {
      if (e.target !== this.el || e.animationName !== animationName) return

      this.finish()
    }

    this.el.addEventListener("animationend", this.onAnimationEnd)
  },

  finish() {
    this.clearListener()
    this.pushEvent("finish_row_effect", {id: this.el.dataset.todoId})
  },

  clearListener() {
    if (this.onAnimationEnd) {
      this.el.removeEventListener("animationend", this.onAnimationEnd)
      this.onAnimationEnd = null
    }
  },

  initLongPress() {
    if (!this.el.dataset.menuId) return

    this.pressTimer = null
    this.pressFired = false

    const start = (e) => {
      if (e.target.closest(INTERACTIVE)) return
      this.pressFired = false
      this.cancelPress()
      this.pressTimer = setTimeout(() => {
        this.pressFired = true
        this.showMenu()
      }, LONG_PRESS_MS)
    }

    const cancel = () => this.cancelPress()

    this.el.addEventListener("touchstart", start, {passive: true})
    this.el.addEventListener("touchend", cancel)
    this.el.addEventListener("touchmove", cancel, {passive: true})
    this.el.addEventListener("touchcancel", cancel)
    this.el.addEventListener("mousedown", start)
    this.el.addEventListener("mouseup", cancel)
    this.el.addEventListener("mouseleave", cancel)
    this.el.addEventListener("contextmenu", (e) => {
      if (this.pressFired) e.preventDefault()
    })
  },

  showMenu() {
    const menu = document.getElementById(this.el.dataset.menuId)
    if (!menu) return

    document.querySelectorAll("[data-todo-actions-menu]").forEach((m) => {
      if (m !== menu) m.style.display = "none"
    })

    menu.style.display = "flex"

    const onDoc = (e) => {
      if (menu.contains(e.target)) return
      menu.style.display = "none"
      document.removeEventListener("touchstart", onDoc, true)
      document.removeEventListener("mousedown", onDoc, true)
    }

    // Defer so the press that opened the menu doesn't immediately close it.
    setTimeout(() => {
      document.addEventListener("touchstart", onDoc, true)
      document.addEventListener("mousedown", onDoc, true)
    }, 0)
  },

  cancelPress() {
    if (this.pressTimer) {
      clearTimeout(this.pressTimer)
      this.pressTimer = null
    }
  },
}
