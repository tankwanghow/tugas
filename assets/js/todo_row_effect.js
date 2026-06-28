const ANIMATION_NAME = {
  created: "todo-row-created",
  updated: "todo-row-updated",
  completed: "todo-row-completed",
  canceled: "todo-row-canceled",
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
    this.hideMenu()
    this.clearLongPress()
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

    this.onPressStart = (e) => {
      if (e.target.closest(INTERACTIVE)) return
      this.pressFired = false
      this.cancelPress()
      this.pressTimer = setTimeout(() => {
        this.pressFired = true
        this.showMenu()
      }, LONG_PRESS_MS)
    }

    this.onPressCancel = () => this.cancelPress()

    this.onContextMenu = (e) => {
      if (this.pressFired) e.preventDefault()
    }

    this.el.addEventListener("touchstart", this.onPressStart, {passive: true})
    this.el.addEventListener("touchend", this.onPressCancel)
    this.el.addEventListener("touchmove", this.onPressCancel, {passive: true})
    this.el.addEventListener("touchcancel", this.onPressCancel)
    this.el.addEventListener("mousedown", this.onPressStart)
    this.el.addEventListener("mouseup", this.onPressCancel)
    this.el.addEventListener("mouseleave", this.onPressCancel)
    this.el.addEventListener("contextmenu", this.onContextMenu)
  },

  clearLongPress() {
    if (!this.onPressStart) return

    this.el.removeEventListener("touchstart", this.onPressStart)
    this.el.removeEventListener("touchend", this.onPressCancel)
    this.el.removeEventListener("touchmove", this.onPressCancel)
    this.el.removeEventListener("touchcancel", this.onPressCancel)
    this.el.removeEventListener("mousedown", this.onPressStart)
    this.el.removeEventListener("mouseup", this.onPressCancel)
    this.el.removeEventListener("mouseleave", this.onPressCancel)
    this.el.removeEventListener("contextmenu", this.onContextMenu)
    this.onPressStart = null
    this.onPressCancel = null
    this.onContextMenu = null
  },

  showMenu() {
    const menu = document.getElementById(this.el.dataset.menuId)
    if (!menu) return

    document.querySelectorAll("[data-todo-actions-menu]").forEach((m) => {
      if (m !== menu) m.style.display = "none"
    })

    this.clearMenuListeners()

    menu.style.display = "flex"

    this.onDocClick = (e) => {
      if (menu.contains(e.target)) return
      this.hideMenu()
    }

    // Defer so the press that opened the menu doesn't immediately close it.
    this.menuOpenTimer = setTimeout(() => {
      document.addEventListener("touchstart", this.onDocClick, true)
      document.addEventListener("mousedown", this.onDocClick, true)
    }, 0)
  },

  clearMenuListeners() {
    if (this.menuOpenTimer) {
      clearTimeout(this.menuOpenTimer)
      this.menuOpenTimer = null
    }

    if (this.onDocClick) {
      document.removeEventListener("touchstart", this.onDocClick, true)
      document.removeEventListener("mousedown", this.onDocClick, true)
      this.onDocClick = null
    }
  },

  hideMenu() {
    this.clearMenuListeners()

    if (this.el.dataset.menuId) {
      const menu = document.getElementById(this.el.dataset.menuId)
      if (menu) menu.style.display = "none"
    }
  },

  cancelPress() {
    if (this.pressTimer) {
      clearTimeout(this.pressTimer)
      this.pressTimer = null
    }
  },
}