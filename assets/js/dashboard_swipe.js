// Mobile dashboard: three full-width panels (Someday | Calendar | Todos).
// Native horizontal scroll + scroll-snap; hint buttons jump between panels.
export const DashboardSwipe = {
  mounted() {
    this.swipeEl = this.el.querySelector("#m-dashboard-swipe")
    this.panelIndex = 1
    this.onScroll = this.onScroll.bind(this)
    this.onGoClick = this.onGoClick.bind(this)

    if (this.swipeEl) {
      this.swipeEl.addEventListener("scroll", this.onScroll, {passive: true})
    }

    this.el.querySelectorAll("[data-dashboard-go]").forEach(btn => {
      btn.addEventListener("click", this.onGoClick)
    })

    this.scrollToPanel(this.panelIndex, false)
  },

  updated() {
    this.scrollToPanel(this.panelIndex, false)
    this.updateIndicators(this.panelIndex)
  },

  destroyed() {
    if (this.swipeEl) {
      this.swipeEl.removeEventListener("scroll", this.onScroll)
    }

    this.el.querySelectorAll("[data-dashboard-go]").forEach(btn => {
      btn.removeEventListener("click", this.onGoClick)
    })
  },

  onGoClick(event) {
    const index = Number(event.currentTarget.dataset.dashboardGo)
    if (Number.isNaN(index)) return

    this.panelIndex = index
    this.scrollToPanel(index, true)
  },

  onScroll() {
    const w = this.swipeEl?.clientWidth
    if (!w) return

    this.panelIndex = Math.round(this.swipeEl.scrollLeft / w)
    this.updateIndicators(this.panelIndex)
  },

  scrollToPanel(index, smooth) {
    const w = this.swipeEl?.clientWidth
    if (!w) return

    this.swipeEl.scrollTo({left: w * index, behavior: smooth ? "smooth" : "instant"})
    this.updateIndicators(index)
  },

  updateIndicators(index) {
    this.el.querySelectorAll("[data-dashboard-panel]").forEach(dot => {
      const active = Number(dot.dataset.dashboardPanel) === index
      dot.classList.toggle("bg-primary", active)
      dot.classList.toggle("bg-base-content/20", !active)
    })

    this.el.querySelectorAll("[data-dashboard-go]").forEach(btn => {
      const active = Number(btn.dataset.dashboardGo) === index
      btn.classList.toggle("text-primary", active)
      btn.classList.toggle("font-semibold", active)
      btn.classList.toggle("text-base-content/50", !active)
    })
  },
}