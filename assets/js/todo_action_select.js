export const TodoActionSelect = {
  mounted() {
    this.el.addEventListener("change", (event) => {
      const action = event.target.value
      if (!action) return

      const id = this.el.dataset.todoId

      if (action === "delete" && !window.confirm("Delete this todo?")) {
        event.target.value = ""
        return
      }

      this.pushEvent("todo_action", {id, action})
      event.target.value = ""
    })
  },
}