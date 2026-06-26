const ANIMATION_NAME = {
  created: "todo-row-created",
  updated: "todo-row-updated",
  deleted: "todo-row-deleted",
}

export const TodoRowEffect = {
  mounted() {
    this.watch()
  },

  updated() {
    this.watch()
  },

  destroyed() {
    this.clearListener()
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
}