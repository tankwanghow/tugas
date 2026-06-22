// Direct (plain HTTP) document upload — replaces LiveView's socket upload for
// document files. Why: on mobile, opening the camera/file picker backgrounds the
// page; a long capture lets the LiveView socket time out, the server process
// dies, and the reconnect remounts fresh — discarding any in-flight socket
// upload (the file was silently lost, regardless of size). This hook instead:
//
//   1. opens a *transient* <input type=file> created in document.body (NOT in
//      LiveView's managed DOM), so a remount can't destroy the selection;
//   2. validates size client-side (fast feedback, avoids a doomed big upload);
//   3. POSTs the file over a normal HTTP request (XHR) to DocumentController,
//      which does not depend on the live socket and survives backgrounding;
//   4. refreshes the LiveView (or reloads) once the file is saved.
//
// Size limits are still enforced authoritatively server-side; this is the fast
// path. See ArgusWeb.DocumentController.create/2.
import {
  persistUploadError,
  clearUploadError,
  showClientSlotError,
  clearClientSlotError,
} from "./upload_ui_persist"

const SKIP_EXT = new Set(["gif", "svg"])
const IMAGE_EXT = new Set(["jpg", "jpeg", "png", "webp", "avif", "bmp", "heic", "heif"])
const VIDEO_EXT = new Set(["mp4", "webm", "mov", "ogg", "ogv", "m4v"])

function extension(name) {
  const dot = name.lastIndexOf(".")
  return dot >= 0 ? name.slice(dot + 1).toLowerCase() : ""
}

function fileKind(name, type) {
  const ext = extension(name)
  if (ext === "pdf") return "pdf"
  if (VIDEO_EXT.has(ext) || type?.startsWith("video/")) return "video"
  if (IMAGE_EXT.has(ext) || ext === "gif" || ext === "svg" || type?.startsWith("image/")) {
    return "image"
  }
  return "other"
}

function kindLabel(kind) {
  if (kind === "image") return "images"
  if (kind === "video") return "videos"
  if (kind === "pdf") return "PDFs"
  return "this file type"
}

function tooLargeMessage(kind, limitBytes) {
  return `File is too large (max ${Math.floor(limitBytes / 1_000_000)} MB for ${kindLabel(kind)}).`
}

function scaledDimensions(width, height, maxEdge) {
  if (width <= maxEdge && height <= maxEdge) return [width, height]
  if (width >= height) return [maxEdge, Math.round((height * maxEdge) / width)]
  return [Math.round((width * maxEdge) / height), maxEdge]
}

async function resizeImageFile(file, {maxEdge, quality, minBytes}) {
  if (file.size < minBytes) return file

  // Detect "image" by extension OR MIME type — camera/gallery files sometimes
  // arrive with an image content-type but a missing/odd extension, and we still
  // want to downscale those. Skip animated GIF / vector SVG.
  const ext = extension(file.name)
  const type = file.type || ""
  const isImage = IMAGE_EXT.has(ext) || type.startsWith("image/")
  const skip = SKIP_EXT.has(ext) || type === "image/gif" || type === "image/svg+xml"
  if (!isImage || skip) return file

  let bitmap
  try {
    bitmap = await createImageBitmap(file)
  } catch (_e) {
    return file
  }

  const [width, height] = scaledDimensions(bitmap.width, bitmap.height, maxEdge)
  const canvas = document.createElement("canvas")
  canvas.width = width
  canvas.height = height
  canvas.getContext("2d").drawImage(bitmap, 0, 0, width, height)
  bitmap.close()

  const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/jpeg", quality / 100))
  if (!blob || blob.size >= file.size) return file

  const base = file.name.replace(/\.[^.]+$/, "") || "upload"
  return new File([blob], `${base}.jpg`, {type: "image/jpeg", lastModified: Date.now()})
}

function csrfToken() {
  return document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || ""
}

export const UploadDirect = {
  mounted() {
    this._onClick = e => {
      e.preventDefault()
      this.pick()
    }
    this.el.addEventListener("click", this._onClick)

    this._controls = this.el.closest("[data-upload-slot-controls]")
    this._dismiss = this._controls?.querySelector("[data-client-upload-dismiss]")
    if (this._dismiss) {
      this._onDismiss = () => {
        clearClientSlotError(this.el.dataset.idPrefix, this.el.dataset.slot)
        clearUploadError(this.el.dataset.obligationId)
      }
      this._dismiss.addEventListener("click", this._onDismiss)
    }
  },

  destroyed() {
    this.el.removeEventListener("click", this._onClick)
    if (this._dismiss && this._onDismiss) this._dismiss.removeEventListener("click", this._onDismiss)
  },

  opts() {
    const d = this.el.dataset
    return {
      maxEdge: parseInt(d.maxEdge || "1920", 10),
      quality: parseInt(d.quality || "85", 10),
      minBytes: parseInt(d.minBytes || "50000", 10),
    }
  },

  limitFor(kind) {
    const d = this.el.dataset
    const map = {image: d.limitImage, video: d.limitVideo, pdf: d.limitPdf, other: d.limitOther}
    return parseInt(map[kind] || d.limitOther, 10)
  },

  // Transient input lives in document.body, outside LiveView's DOM, so a
  // remount triggered by backgrounding during the pick can't destroy it.
  pick() {
    const input = document.createElement("input")
    input.type = "file"
    input.style.position = "fixed"
    input.style.left = "-9999px"
    document.body.appendChild(input)
    input.addEventListener("change", () => this.handle(input), {once: true})
    input.click()
  },

  async handle(input) {
    const file = input.files && input.files[0]
    const cleanup = () => input.remove()

    if (!file) {
      cleanup()
      return
    }

    const d = this.el.dataset
    const slot = d.slot
    const kind = fileKind(file.name, file.type)
    const limit = this.limitFor(kind)

    // Downscale images first, so the size limit applies to the (smaller) result:
    // a large photo gets resized rather than rejected.
    let toSend = file
    if (kind === "image") {
      try {
        toSend = await resizeImageFile(file, this.opts())
      } catch (_e) {
        toSend = file
      }
    }
    cleanup()

    if (toSend.size > limit) {
      const message = tooLargeMessage(kind, limit)
      showClientSlotError(d.idPrefix, slot, message)
      // Survive a remount that happened during the pick (camera backgrounding).
      persistUploadError(d.obligationId, d.idPrefix, slot, message)
      return
    }

    this.upload(toSend, slot)
  },

  upload(file, slot) {
    const d = this.el.dataset
    const form = new FormData()
    form.append("file", file)
    if (d.documentSlot) form.append("document_slot", d.documentSlot)
    if (d.eventId) form.append("event_id", d.eventId)

    const xhr = new XMLHttpRequest()
    xhr.open("POST", d.uploadUrl)
    xhr.setRequestHeader("x-csrf-token", csrfToken())
    // NB: don't send `Accept: application/json` — the :browser pipeline runs
    // `plug :accepts, ["html"]` and would 406 a json-only request before the
    // controller runs. The default `*/*` negotiates html; the controller still
    // replies with a JSON body (parsed here by status code).

    this.setBusy(0)
    if (xhr.upload) {
      xhr.upload.onprogress = e => {
        if (e.lengthComputable) this.setBusy(Math.round((e.loaded / e.total) * 100))
      }
    }

    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        // Reset the button: for the always-present "additional" uploader the
        // element persists across the refresh, and its static "Choose file"
        // label isn't restored by the LiveView diff after the hook changed it.
        this.clearBusy()
        clearUploadError(this.el.dataset.obligationId)
        this.refresh()
      } else {
        this.fail(slot, errorMessage(xhr))
      }
    }
    xhr.onerror = () => this.fail(slot, "Upload failed. Please try again.")
    xhr.send(form)
  },

  fail(slot, message) {
    const d = this.el.dataset
    this.clearBusy()
    showClientSlotError(d.idPrefix, slot, message)
    persistUploadError(d.obligationId, d.idPrefix, slot, message)
  },

  setBusy(percent) {
    if (this._origLabel === undefined) this._origLabel = this.el.textContent
    this.el.disabled = true
    this.el.textContent = percent > 0 && percent < 100 ? `Uploading ${percent}%` : "Uploading…"
  },

  clearBusy() {
    this.el.disabled = false
    if (this._origLabel !== undefined) this.el.textContent = this._origLabel
  },

  // The file is already saved server-side; this just refreshes the view. If the
  // socket is down (e.g. it dropped during the pick), reload instead.
  refresh() {
    if (window.liveSocket && window.liveSocket.isConnected()) {
      this.pushEvent("document_uploaded", {})
    } else {
      window.location.reload()
    }
  },
}

function errorMessage(xhr) {
  try {
    const body = JSON.parse(xhr.responseText)
    if (body && body.error) return body.error
  } catch (_e) {
    // fall through
  }
  return "Upload failed. Please try again."
}
