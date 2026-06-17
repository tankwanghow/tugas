# Unified Documents view (required cycle-level / other per-step) — design

**Date:** 2026-06-17
**Status:** Approved (pending spec review)

## Problem

The obligation Documents modal has two stacked sections that are two views of the
same data:

- **COMPLETION DOCUMENTS** (top) — a per-slot checklist with upload affordances.
- **ON THIS STEP** (bottom) — the actual uploaded files with their actions.

The redundancy is explicit: satisfied slots in the top section literally say
"Manage below", pointing at the bottom section for the same file. Worse, the two
sections describe **different document sets**:

- The top checklist's "✓ Uploaded" is computed **cycle-wide** — `satisfied_slots/1`
  flat-maps over every event's documents.
- The bottom list shows only the **current event's** documents
  (`@documents_modal_event.documents`).

So a slot can show ✓ because its file was uploaded on a different step
(e.g. `in_progress`), while that file is absent from the list below — a latent
contradiction the split hides.

## Goal

Remove the duplication by giving each file exactly one home, split by what the file
is for:

- **Required (completion-slot) files** belong to the **cycle** (completion is a
  cycle-wide contract) → one cycle-level view, slot-centric.
- **Other (supporting) files** belong to the **step** they were added on → a
  per-step view.

## File classification

A document is classified by its `document_slot` against the obligation's **current**
snapshot `complete_documents`:

- **Required** — `document_slot` is in the snapshot's required set.
- **Other / supporting** — `document_slot` is `nil`, or holds a name **not** in the
  current required set (a "stale slot" left behind after a type change; see Type slot
  changes).

Classification is computed at render/validation time from the slot value; document
rows are never mutated to change classification.

## Decisions

1. **Two surfaces** (not one merged modal):
   - **A. Completion Documents** — cycle-level, one button on the obligation.
   - **B. Step Files** — per-step, a button on each event row.
2. **Each surface owns its voided files.** Voided required files show in Surface A's
   voided section; voided other files show in their step's Surface B voided area.
3. **Voided files remain downloadable.** The download link stays on voided rows.
4. **Slots are immutable after upload** (already shipped) and **Replace is removed**
   (already shipped) — to change a slot's file you delete/void and re-upload.

## Surface A — Completion Documents (cycle-level)

**Entry point:** a single "Completion documents" button in the obligation action
area opens a cycle-wide modal. (Replaces the old per-event "Documents" buttons for
required docs.)

**Component:** `ArgusWeb.ObligationCompletionDocuments` — `completion_documents/1`.

**Inputs (assigns):** `obligation`, `current_scope`, `entity_slug`,
`documents` (cycle-wide, `events |> Enum.flat_map(& &1.documents)`),
`required_slots` (parsed snapshot `complete_documents`), upload state
(`@uploads.document`, `upload_slot_target`, `upload_slot_entries`), `uploadable?`,
`voiding_document_id`, `void_reason_required?`.

**Layout:**

```
COMPLETION DOCUMENTS
  ✓ Form A     SOCSO+EIS_5_2026.txt    17 Jun 03:37   [Delete]
  ✓ Receipt A  StatementRequest(1).pdf 17 Jun 03:37   [Delete]
  ✗ Tax form   [Choose file]           (required, not uploaded)

VOIDED REQUIRED FILES
  ~~EPF_5_2026.csv~~  Form A   16 Jun 08:33   Void reason: wrong period
```

- **Satisfied slot row:** ✓ + slot name + live required file (download link,
  timestamp) + Delete/Void per auth.
- **Unsatisfied slot row:** ✗ + slot name + inline "Choose file" uploader (shared
  hidden-input picker), marked required.
- **Voided section:** voided **required** files (slot in current required set), across
  all steps — downloadable, struck-through, with slot badge and void reason. Renders
  only when non-empty.

**Upload target:** the cycle's single workable event — `in_progress` if it exists,
else `open` — resolved in the LiveView and passed to `add_document/5`. Uploaders
render only when `uploadable?` (live cycle, a workable event exists,
`can_add_document?`); otherwise read-only.

## Surface B — Step Files (per-step)

**Entry point:** a "Files" button on each event row in the timeline opens that step's
modal.

**Component:** `ArgusWeb.ObligationStepFiles` — `step_files/1`.

**Inputs (assigns):** `event`, its `documents`, `obligation`, `current_scope`,
`entity_slug`, upload state, `uploadable?` (this event), `voiding_document_id`,
`void_reason_required?`.

**Content (for one event):**
- That step's live **other** files (no-slot or stale-slot), each with download link,
  timestamp, and Delete/Void. Shown as plain supporting files with **no** slot badge
  — a stale-slot file is no longer tied to a live slot, so its old slot name is not
  surfaced.
- That step's voided other files — downloadable, struck-through, with reason.
- An "Additional file" uploader when the step is uploadable.

**Upload target:** this event (a file added here is a supporting file on this step).

## Behavior — actions & auth (rules unchanged, relocated)

- **Delete** on a live file: shown when `document_deletable?/3` (within 48h, live
  cycle, voider rights).
- **Void**: shown when `document_voidable?/3` (after 48h / admin / locked cycle);
  reuses the inline void-reason form gated by `void_reason_required?`.
- Done/cancelled cycle → no uploaders, no Delete on either surface; admin Void still
  possible, moving the file into the relevant voided area.

## Type slot changes (admin edits `complete_documents`)

Already implemented by `update_type/3` → `propagate_complete_documents_to_live/3`,
preserved as-is:

- The propagation query targets `live(Obligation)` only (`status == "active" AND
  completed_at IS NULL`).
- **Completed and cancelled** obligations are excluded → their snapshot
  `complete_documents` stays frozen, and their files keep classifying against the old
  required set. Unchanged.
- **Open / in-progress** obligations have their snapshot updated to the new required
  set (audit-logged).

Interaction with classification: when a slot is removed or renamed, a live
obligation's required set updates, so a file tagged with the now-missing slot is no
longer "required" — it is automatically reclassified as a supporting file and moves
from Surface A to its step's Surface B (shown without a slot badge, since the slot no
longer exists). No document rows are mutated; if the admin later re-adds the slot, a
file still tagged with that name counts again.

## Entry points & LiveView state

Desktop `obligation_live/show.ex` and mobile `mobile_live/obligation_show.ex`:

- Add a boolean `show_completion_modal` for Surface A; `open_completion_modal` /
  `close_completion_modal`; the Done modal's "missing documents" link
  (`open_documents_from_done`) opens Surface A.
- Keep event-keyed modal state for Surface B (`step_files_modal_event_id`), opened by
  the per-event "Files" button.
- Only one modal is open at a time, so both surfaces share the single `:document`
  upload config.
- `event_uploadable?/2` stays for Surface B; Surface A uses a cycle-level
  `uploadable?` plus the resolved workable event for its upload target.

## Files touched

- **New:** `lib/argus_web/components/obligation_completion_documents.ex`,
  `lib/argus_web/components/obligation_step_files.ex` (the colocated `SlotFilePicker`
  hook moves to whichever component(s) host the picker).
- **Deleted:** `lib/argus_web/components/obligation_document_upload.ex`,
  `lib/argus_web/components/obligation_document_list.ex`.
- **Edited:** `lib/argus_web/live/obligation_live/show.ex`,
  `lib/argus_web/live/mobile_live/obligation_show.ex` (render, modal state, handlers,
  upload-target resolution); `lib/argus_web/controllers/document_controller.ex`
  (allow downloading voided files).
- **Context `obligations.ex`:** no new functions; reuses `add_document/5`,
  `delete_document/3`, `void_document/4`, and preloaded cycle documents.
  `propagate_complete_documents_to_live/3` unchanged. `LiveUpload` / `UploadValidate`
  remain.

## Testing (TDD)

Surface A (cycle completion):
1. Satisfied slot shows its live required file inline with Delete; unsatisfied slot
   shows an inline uploader.
2. Uploading to a slot attaches to the workable event and the slot flips to ✓.
3. A voided required file appears in the cycle voided section (downloadable,
   struck-through, reason) and nowhere else.
4. Done/cancelled cycle → read-only (no uploader, no Delete).

Surface B (step files):
5. A no-slot file uploaded on a step appears in that step's Files modal, not in the
   cycle completion view.
6. A voided other file appears in that step's voided area, downloadable.

Type slot changes:
7. Removing a required slot on the type reclassifies a live obligation's matching
   file as a supporting file (gone from Surface A, present in Surface B, no badge);
   a completed obligation's file is unchanged.

Voided download:
8. `DocumentController.show` serves a voided file (regression for the relaxed guard).

Existing document tests updated to the new element ids/structure. Mobile is covered
by the shared components.

## Out of scope

- No change to the document data model or storage layout.
- No change to completion rules beyond classification by current required set
  (already the effective behavior).
- No reintroduction of Replace or post-upload slot editing (both removed earlier).
