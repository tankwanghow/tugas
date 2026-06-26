// Scrolls the todo row referenced by `?highlight=<id>` (set when arriving from the team
// log) into view. The visual flash itself is applied server-side via the row's
// `todo-row-highlight` class + CSS animation; this hook only handles scrolling.
//
// The hook lives on the stable page wrapper (NOT the `phx-update="stream"` <ul>, where a
// hook is unreliable). It scrolls from two triggers, whichever lands:
//   1. the server's "highlight_todo" push event (dispatched after the DOM is patched), and
//   2. a `mounted` read of `data-highlight-id` (fallback if the event is missed).
// Each trigger re-asserts the scroll a few times to beat LiveView's scroll-to-top on
// navigation and to wait for freshly-streamed rows to lay out.
export const TodoHighlight = {
  mounted() {
    this.handleEvent("highlight_todo", ({id}) => this.focusRow(id))

    const id = this.el.dataset.highlightId
    if (id) this.focusRow(id)
  },

  focusRow(id) {
    if (!id || id === this.lastId) return
    this.lastId = id

    const tryScroll = () => {
      const row = document.querySelector(`[data-todo-id="${CSS.escape(id)}"]`)
      if (row) row.scrollIntoView({behavior: "smooth", block: "center"})
    }

    requestAnimationFrame(tryScroll)
    setTimeout(tryScroll, 120)
    setTimeout(tryScroll, 300)
  },
}
