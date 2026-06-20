# Obligation close-model overhaul — timestamp-based states + self-describing events

**Status:** approved design, pre-implementation
**Date:** 2026-06-20
**Context:** Argus is not yet deployed, so the schema may be changed freely (no
backward-compat / data-migration constraints). See `[[breaking-changes-ok-predeploy]]`.

## Problem

Today a cycle's "doneness" is a timestamp (`completed_at`) but its "not-done close"
is a string `status = "active" | "cancelled"`. Three different actions — **Cancel**
(one-off), **Skip** (recurring occurrence), and **End series** (stop recurrence) — all
write `status: "cancelled"` plus a `cancelled` event. As a result:

- They are indistinguishable in storage and in the event timeline.
- There is no way to badge "Skipped" vs "Cancelled" vs "Series ended".
- The model is asymmetric: done is a timestamp, cancelled is a status string.

## Goals

1. Make every terminal state a **timestamp** (symmetry with `completed_at`); drop the
   `status` string entirely.
2. Make the **event log self-describing** — the terminal event status states what
   happened, so the badge is a direct read with no inference.
3. Keep **provenance on the event** (who/when/note) — no duplicated `*_by` columns.
4. Simplify the action vocabulary: a single **Skip** replaces Cancel + Skip.

## Decisions (resolved during brainstorming)

- **Unify Cancel and Skip into one "Skip"** action. There is no `cancelled` state.
  Terminal event statuses are `done | skipped | series_ended`.
- **Liveness column is named `closed_at`** (the dual of `completed_at`), set by both
  Skip and End series. The event status disambiguates which kind of close it was.
- **No `*_by` columns** for done/skip/end-series — the actor is the terminal event's
  `status_by_id` (each terminal event is singular per cycle, so it is unambiguous).
- **completed-in-error keeps its columns** (`completed_in_error_at/_by_id/_reason`)
  because it deliberately creates *no* event (the FSM stays forward-only); it is the
  one explicit exception to "actor lives on the event."

## Data model

`Argus.Obligations.Obligation`:

| Column | Set by | Meaning |
|--------|--------|---------|
| `completed_at` (keep) | Done | cycle completed |
| `closed_at` (**new**, `:utc_datetime`) | Skip, End series | cycle closed without completing |
| `series_ended_at` (keep) | End series | recurrence stopped (blocks future spawning) |
| `completed_in_error_at` / `_by_id` / `_reason` (keep) | mark-completed-in-error | unchanged exception (no event) |
| ~~`status`~~ | — | **dropped** |

Notes:
- `series_ended_at` always implies `closed_at` (End series closes the current cycle).
- Spawned successors never carry `closed_at`/`series_ended_at`.

**Liveness predicate** (`Obligations.live/1`): `completed_at IS NULL AND closed_at IS NULL`.
The `obligations_one_live_cycle_per_series` partial unique index is rebuilt on this
predicate.

**Derived cycle status** (columns only — no event load required):

```
completed_at  set            -> :completed
series_ended_at set          -> :series_ended   (check before :skipped)
closed_at set                -> :skipped
else                         -> :live
```

## Event FSM

`open -> in_progress* -> done | skipped | series_ended`

- Add `Event.terminal_statuses/0 => ~w(done skipped series_ended)` as the single source
  of truth. `Event` `validate_inclusion` allows `open | in_progress | done | skipped |
  series_ended`. `ensure_progressable/1` checks `e.status in Event.terminal_statuses()`
  instead of the hardcoded `["done","cancelled"]`.
- `open` remains singular per cycle; `in_progress` may repeat; the terminal event is
  singular.

## Domain actions (3, down from 4)

- **`complete/3`** — unchanged behavior: stamp `completed_at`, insert `done` event; if
  `Recurrence.recurring?(type)` and not series-ended, require `next_due_by` and spawn the
  next cycle. The guarded close (`update_all ... WHERE live`) is retained.
- **`skip/3`** — **merges `cancel_obligation` + `skip_cycle`.** Stamp `closed_at`, insert a
  `skipped` event; if recurring & not series-ended, require `next_due_by` and spawn the next
  cycle; for a one-off, just close (no successor). Note is required (`validate_action_note`).
- **`end_series/3`** — stamp `closed_at` + `series_ended_at`, insert a `series_ended` event;
  never spawn. Note required.

`validate_correctable/1` and `locked_cycle?/1` switch from `status` checks to columns:
- correctable: `completed_at` set AND `closed_at` nil AND `completed_in_error_at` nil.
- locked: not live, i.e. `completed_at` set OR `closed_at` set.

## Authorization

`:cancel_obligation` and `:skip_cycle` collapse into a single **`:skip`** (manager/admin,
same roles as today). `:end_series` unchanged. `Authorization.can?` updated accordingly.

## UI

- **`ObligationStatusBadge`** renders, for non-live cycles: **Done** (success),
  **Skipped** (warning), **Series ended** (neutral). Used by dashboard cards + show header.
- **Show pages** (desktop + mobile): every live cycle shows one **Skip** button; recurring
  cycles additionally show **End series**. The skip modal asks for `next_due_by` only when
  recurring (mirrors Done). The "Cancel" button/label is removed. References to the
  `cancelled` status in summaries/banners become skipped/series-ended aware.
- **`EventMeta`** adds `skipped` -> "Skipped" and `series_ended` -> "Series ended"
  (with colors) so the timeline reads truthfully.
- **List filter** (`ObligationLive.IndexHelpers`): the `cancelled` status becomes
  **`skipped`**, defined as `closed_at IS NOT NULL` (covers both skipped and series-ended
  cycles; their badges differentiate). `My Live / My Completed / Live / Completed / All`
  unchanged. `cycle_status`, `status_label`, `empty_message`, and the `list_obligations`
  status query are updated to the column-based model.

## Testing

TDD per change. Migrate all `status`/`cancelled` assertions:
- `cancel_obligation` tests -> `skip` (one-off path, no successor).
- `skip_cycle` tests -> `skip` (recurring path, spawns successor, requires `next_due_by`).
- event status `cancelled` -> `skipped` / `series_ended`.
- badge text `Cancelled` -> `Skipped` / `Series ended`.
- liveness assertions move from `status` to `closed_at`/`completed_at`.
- filter tab rename `cancelled` -> `skipped`.

## Out of scope

- Converting completed-in-error into an event (it stays a stamp; forward-only FSM).
- Any data migration (app not deployed; dev/test DBs are recreated).
- New reporting/analytics on skip vs series-ended beyond the badge + filter.
```
