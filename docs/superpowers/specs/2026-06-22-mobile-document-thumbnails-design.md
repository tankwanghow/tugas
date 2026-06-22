# Mobile Document Thumbnails — Design

**Date:** 2026-06-22
**Status:** Approved (design)
**Scope:** Mobile UI only. Desktop keeps its current list layout and will be converted in a
follow-up.

## Goal

On mobile, replace the row/list + upload-button presentation of documents with a Twitter-style
grid of **thumbnail tiles** that show a real preview of each file. Applies to the two mobile
modals where files are managed:

1. **Completion documents** modal — required slots (`ObligationCompletionDocuments`).
2. **Files** modal — supporting/per-step files (`ObligationStepFiles`).

The mobile **timeline** inline file list is out of scope and unchanged.

## Staging mechanism (mobile-first, desktop later)

`completion_documents/1` and `step_files/1` are shared by desktop and mobile. Add a `layout` attr:

- `:list` (default) — current presentation; desktop keeps this.
- `:tiles` — new thumbnail grid; the mobile views pass this.

All non-presentation plumbing (slot classification, upload wiring, delete/void events) stays
shared; only the rendering branches on `layout`. Extract a `file_tile/1` helper for a single tile
so the two modals share tile markup.

## Tile grid

- 3-column grid of **square** tiles (`aspect-square`).
- Truncated label under each tile: slot name (required) or filename (supporting).
- Tapping a tile opens the existing in-page **preview modal** (`doc_preview_modal/1`) by reusing
  the `data-doc-preview` / `data-doc-kind` / `data-doc-name` / `href` attributes already consumed
  by the click handler in `app.js`. No new modal.

## Tile content by file kind

Classification is the existing `DocumentHelpers.file_kind/1` (`:image | :video | :pdf | :other`).

- **image** — `<img>` with `object-cover`, `loading="lazy"`.
- **video** — `<video muted playsinline preload="metadata">` (first frame) with a ▶ overlay; no
  controls in the tile.
- **pdf** — first page rendered to a `<canvas>` via the vendored pdf.js, using a new **`PdfThumb`**
  client hook that reads `data-src` and renders page 1. The hook uses the `pdfjsLib` already
  imported in `app.js`; it is registered in the LiveSocket `hooks` map (alongside the colocated
  hooks).
- **other** — a card showing the `file_kind` type icon + filename (no media).

## Required slots (Completion modal, `:tiles`)

- **Satisfied slot** — file tile + slot label + ⋮ corner menu.
- **Unsatisfied slot** — a dashed **"+" tile** labeled with the slot name. Tapping it opens the
  native file picker (existing `select_upload_slot` + `SlotFilePicker` hook flow). A staged file
  renders as a tile with a ✅ confirm / ❌ clear overlay. If the staged file is invalid (e.g. too
  large), the red error message shows and ✅ is hidden (behavior already implemented in the list
  layout via `LiveUpload.entry_error_messages/2`; reused here).

## Supporting files (Files modal, `:tiles`)

- Grid of supporting-file tiles, each with a ⋮ corner menu.
- A trailing dashed **"+" tile** to add an additional file (same staged → confirm/clear flow).
- **Voided** files appear in a separate, dimmed section as tiles (still tap-to-preview/download,
  with a "voided" badge), preserving the audit-download behavior.

## Actions (⋮ corner menu)

- The ⋮ button is a **sibling** of the preview-trigger element (not a descendant), so tapping ⋮
  does not bubble to the `data-doc-preview` click handler.
- Menu options: **Delete** (when `document_deletable?`) and **Void** (when `document_voidable?`;
  reveals the inline reason form when `void_reason_required?`).
- Reuses existing events: `request_delete_document` / `delete_document` /
  `cancel_delete_document`, `void_document` / `confirm_void_document` / `cancel_void_document`.

## JavaScript

- New `PdfThumb` hook in `app.js` (uses imported `pdfjsLib`): on `mounted`, load the PDF from
  `data-src` and render page 1 to the element's canvas, sized to the tile (× devicePixelRatio for
  crispness). Registered via `hooks: {...colocatedHooks, PdfThumb}`.
- Images and video need no JS.
- Tap-to-preview reuses the existing delegated `[data-doc-preview]` click handler — no change.

## Testing

Mobile LiveView tests (`test/argus_web/live/mobile_live_test.exs` and/or the obligation mobile
show test):

- Tiles render for each file kind (image/video/pdf/other) in both modals.
- An unsatisfied required slot renders a "+" picker tile; staging a file shows confirm/clear.
- A staged oversized file hides the confirm control and shows the error (mobile).
- ⋮ Delete and Void still function (delete reopens the slot tile; void moves the file to the
  voided section).

## Out of scope

- Desktop tile layout (follow-up; the `:list` default stays).
- Mobile timeline inline file list.
- Any change to upload limits, the preview modal internals, or the document controller.
