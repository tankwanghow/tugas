// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/argus"
import topbar from "../vendor/topbar"
import * as pdfjsLib from "../vendor/pdfjs/pdf.min.mjs"
import {UploadDirect} from "./upload_direct"
import {UploadUiPersist} from "./upload_ui_persist"
import {TodoRowEffect} from "./todo_row_effect"
import {TodoHighlight} from "./todo_highlight"

// The worker is a separate esbuild entry (js/pdf.worker.js) served as a static
// asset; the browser only fetches it when a PDF is actually previewed.
pdfjsLib.GlobalWorkerOptions.workerSrc = "/assets/js/pdf.worker.js"

// First-page PDF thumbnail for mobile obligation show document tiles.
const PdfThumb = {
  async mounted() {
    const url = this.el.dataset.src
    if (!url) return

    try {
      const pdf = await pdfjsLib.getDocument(url).promise
      const page = await pdf.getPage(1)
      const cssWidth = this.el.clientWidth || 100
      const dpr = window.devicePixelRatio || 1
      const cssScale = cssWidth / page.getViewport({scale: 1}).width
      const viewport = page.getViewport({scale: cssScale * dpr})
      const canvas = this.el
      canvas.width = viewport.width
      canvas.height = viewport.height
      canvas.style.width = "100%"
      canvas.style.height = "100%"
      await page.render({canvasContext: canvas.getContext("2d"), viewport}).promise
    } catch (_e) {
      // Tile falls back to the generic PDF icon in HEEx if rendering fails.
    }
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, PdfThumb, UploadDirect, UploadUiPersist, TodoRowEffect, TodoHighlight},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

window.addEventListener("phx:store-dashboard-filter", event => {
  fetch("/session/dashboard-filter", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "X-CSRF-Token": csrfToken,
    },
    body: new URLSearchParams(event.detail),
  })
})

// Close daisyUI checkbox-driven modals (e.g. mobile "More" sheet) on Escape.
document.addEventListener("keydown", e => {
  if (e.key === "Escape") {
    document.querySelectorAll("input.modal-toggle:checked").forEach(toggle => {
      toggle.checked = false
    })
  }
})

// In-page preview for uploaded document links (see CoreComponents.doc_link/1).
// Images, videos and PDFs open in the shared #doc-preview-modal; other file
// types fall through to the browser's default (open/download in a new tab).
function openDocPreview(link) {
  const modal = document.getElementById("doc-preview-modal")
  if (!modal) return false

  const kind = link.dataset.docKind
  const name = link.dataset.docName || "file"
  const src = link.getAttribute("href")

  const body = modal.querySelector("#doc-preview-body")
  const download = modal.querySelector("#doc-preview-download")

  if (kind === "image") {
    const img = document.createElement("img")
    img.src = src
    img.alt = name
    img.className = "mx-auto max-w-full max-h-[72vh] object-contain"
    body.replaceChildren(img)
  } else if (kind === "video") {
    const video = document.createElement("video")
    video.src = src
    video.controls = true
    video.className = "mx-auto max-w-full max-h-[72vh]"
    body.replaceChildren(video)
  } else if (kind === "pdf") {
    renderPdf(src, body)
  } else {
    return false
  }

  modal.querySelector("#doc-preview-name").textContent = name
  download.href = src + (src.includes("?") ? "&" : "?") + "download=1"
  download.setAttribute("download", name)
  modal.showModal()
  return true
}

// Render every page of a PDF to a canvas (pdf.js). Canvas works on mobile where
// an <iframe src=*.pdf> typically renders blank or forces a download.
async function renderPdf(url, container) {
  const note = document.createElement("p")
  note.className = "text-sm text-base-content/60 p-4"
  note.textContent = "Loading…"
  container.replaceChildren(note)

  try {
    const pdf = await pdfjsLib.getDocument(url).promise
    const pages = document.createElement("div")
    pages.className = "w-full space-y-4"
    container.replaceChildren(pages)

    const cssWidth = container.clientWidth || 800
    const dpr = window.devicePixelRatio || 1

    for (let n = 1; n <= pdf.numPages; n++) {
      const page = await pdf.getPage(n)
      const cssScale = cssWidth / page.getViewport({scale: 1}).width
      const viewport = page.getViewport({scale: cssScale * dpr})
      const canvas = document.createElement("canvas")
      canvas.width = viewport.width
      canvas.height = viewport.height
      canvas.style.width = "100%"
      canvas.style.height = "auto"
      canvas.className = "mx-auto shadow"
      pages.appendChild(canvas)
      await page.render({canvasContext: canvas.getContext("2d"), viewport}).promise
    }
  } catch (_e) {
    note.className = "text-sm text-error p-4"
    note.textContent = "Couldn't render this PDF. Use Download to open it."
    container.replaceChildren(note)
  }
}

document.addEventListener("click", e => {
  const link = e.target.closest("[data-doc-preview]")
  if (link && openDocPreview(link)) e.preventDefault()
})

// Clear the body on close so videos stop playing and the iframe is released.
// `close` doesn't bubble, so listen in the capture phase.
document.addEventListener("close", e => {
  if (e.target && e.target.id === "doc-preview-modal") {
    e.target.querySelector("#doc-preview-body").replaceChildren()
  }
}, true)

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

