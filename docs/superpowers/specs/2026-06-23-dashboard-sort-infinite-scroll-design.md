# Dashboard sorting + infinite scroll — design

**Date:** 2026-06-23
**Status:** Approved (pending spec review)
**Surface:** `DashboardLive.Index` (Desktop) and `MobileLive.Dashboard` (Mobile), both rendering
via `ArgusWeb.ObligationLive.IndexHelpers` and `Argus.Obligations.list_obligations/2`.

## Problem

The dashboard is the obligation list on both UIs. Today it has **no user-controllable sort**: each
lifecycle has a fixed order (Live = urgency → due_by; Completed = `completed_at` desc; Skipped =
`closed_at` desc; All = `due_by` desc), all applied **in memory** after loading the *entire* result
set, and the search filter (`filter_by_query`) is also in memory.

Two gaps:

1. **No sort control.** Users want to reorder the list (by due date, urgency, title).
2. **Unbounded in-memory load.** Completed and Skipped cycles are append-only history that grows
   without bound; loading them all into the socket to sort/slice does not scale past extended usage.

## Decisions (locked)

- **Filtering and sorting run in SQL** for every lifecycle, with **one** in-memory exception.
- **Pagination is DB-side (keyset cursor)** for every lifecycle, so history scales.
- **The sole in-memory exception:** `sort = urgency AND lifecycle = live`. Urgency depends on each
  type's `reminder_offsets` + the entity-timezone `today`, which is impractical in SQL; and urgency
  is meaningless for done/closed rows (the UI only renders the urgency badge when
  `cycle_status == :live`). So urgency sorting exists only on the Live lifecycle.
- **Sort presets** (dropdown, value → behavior):

  | Label           | value      | Behavior                                             |
  |-----------------|------------|------------------------------------------------------|
  | Due soonest *(default)* | `due_asc`  | `order_by due_by asc`                         |
  | Due latest      | `due_desc` | `order_by due_by desc`                               |
  | Title A–Z       | `title`    | `order_by lower(title) asc`                          |
  | Most urgent     | `urgency`  | urgency rank → `due_by` asc (**Live only**, in memory)|

- **The Sort dropdown is lifecycle-aware:** "Most urgent" is rendered **only when lifecycle = Live**.
  Every other lifecycle hides it and defaults to `due_asc`. A persisted `urgency` value combined with
  a non-live lifecycle **resolves to `due_asc`**.
- **Urgency+Live window = 1 year.** The in-memory path loads live cycles with `due_by` within one
  year of `today` (covers every overdue / due-soon row, since those are within the largest reminder
  offset), sorts them in memory by urgency rank then `due_by`, and continues with the `>1yr` tail
  (uniformly `:ok` urgency) via the normal SQL keyset path ordered by `due_by`.
- **Page size = 25**, a single module constant.
- **Sort persists** per-entity alongside `mine`/`lifecycle`/`query` in the existing
  `dashboard_filters` entry (ETS store + session snapshot + `/session/dashboard-filter` POST),
  default `due_asc`, bogus values rejected.

This is a hybrid: a single SQL keyset path for all lifecycles, plus an in-memory first window only
for Most-urgent-on-Live.

## Architecture

### 1. Context — `Argus.Obligations`

Replace the all-rows load with a paginated, SQL-sorted, SQL-filtered query.

```elixir
# opts: :status, :query, :sort (:due_asc | :due_desc | :title | :urgency),
#       :cursor (opaque keyset cursor | nil), :limit (default 25)
def list_obligations_page(%Scope{} = scope, opts \\ []) ::
  %{rows: [%Obligation{}], cursor: cursor | nil, end?: boolean}
```

- **Filtering in SQL** (`filter_by_query` moves into the query): `ILIKE '%q%'` on `title`, on the
  joined `obligation_type.name`, and on the joined `primary_assignee.email`; plus the literal
  `"unassigned"` match (`primary_assignee_id IS NULL`). Preserves current search semantics.
- **Sorting in SQL** per the preset table. For `:urgency` with a **non-live** status, treat as
  `:due_asc`. For `:urgency` with **live** status, the context returns rows ordered by `due_by`
  (the in-memory urgency re-sort happens in `IndexHelpers`, see §3) — the window bound (`due_by <=
  today + 1yr`) is applied by the LiveView for the first page only.
- **Keyset pagination.** Order by the sort column **plus `id`** as a stable tiebreak. The cursor
  encodes the last row's `(sort_value, id)`; the next page is
  `WHERE (sort_col, id) > (cursor_val, cursor_id)` (direction per sort). `due_by` is `NOT NULL`
  (required on the changeset), so no null-ordering edge cases.
- Keep `:obligation_type` and `:primary_assignee` preloads (urgency + render need them).

Retire `list_obligations/2`'s caller path on the dashboard; the existing fixed `apply_list_order`
clauses collapse into the sort-driven `order_by`. (Other callers, if any, are checked during
implementation and migrated or left on a thin wrapper.)

### 2. Filter persistence — `ArgusWeb.DashboardFilter`

Add `sort` to the per-entity entry, mirroring `mine`/`lifecycle`/`query`:

- `@sorts ~w(due_asc due_desc title urgency)`.
- `session_entry/1` includes `"sort" => param_sort(params["sort"])`; `param_sort/1` whitelists the
  four values, default `"due_asc"`.
- `merge_saved/2` parses `sort` to an atom via a `parse_sort/1` (default `:due_asc`); `defaults/1`
  sets `sort: :due_asc`.
- `assign_filters/2` assigns `:sort`; `current_entry/1` reads `socket.assigns.sort`; the
  `store-dashboard-filter` push payload gains `sort`.
- `DashboardFilterController` / `put_session` already forward arbitrary params — `sort` flows through
  with no controller change beyond passing it (it's in `params`).

### 3. Row building + the urgency exception — `IndexHelpers`

- `load_page(scope, today, mine?, lifecycle, query, sort, cursor)` → `%{rows, cursor, end?}` where
  `rows` are the existing row maps (`obligation`, `cycle_status`, `urgency`, `tier`, `event_count`,
  `latest_event`).
- **Non-urgency, or non-live:** pass straight through from `list_obligations_page/2` (already
  SQL-ordered); build row maps; return cursor/end?.
- **Urgency + Live (in memory):** first page requests live rows with `due_by <= today + 1yr` ordered
  by `due_by`, builds row maps, sorts by `{@urgency_rank[urgency], due_by}`. The cursor/tail: once the
  windowed set is exhausted, subsequent `load_more` falls back to the SQL keyset path on live rows
  with `due_by > today + 1yr` ordered by `due_by` (all `:ok`). `end?` is true when that tail is
  exhausted. This is the only two-mode pagination seam.
- `sort_rows/2` (lifecycle-keyed) is removed; ordering is now SQL-driven except the urgency case
  above.
- `sorts/1` helper returns the dropdown options for a lifecycle: all four for `:live`, the three
  non-urgency for everything else (drives the lifecycle-aware UI).

### 4. LiveView — both dashboards

- **Streams.** Convert `#obligations-list` / `#mobile-obligations` to `phx-update="stream"`,
  satisfying the CLAUDE.md "streams, never `:for`" rule the dashboard currently breaks. Preserve DOM
  ids via `stream/4`'s `dom_id:` (`obligation-row-#{id}` desktop, `m-ob-#{id}` mobile) so existing
  selectors/tests hold. The mobile `obligation_card` gains an `id` attr fed from the stream dom_id.
- **Assigns:** `:sort`, `:cursor`, `:end?`, `:empty?` (can't test `@rows == []` under streams).
- **Sort control:** a `<select name="sort">` with `phx-change="set_sort"`, options from
  `IndexHelpers.sorts(@lifecycle)`. Desktop: in the toolbar row beside the lifecycle dropdown.
  Mobile: in the sticky header row beside the lifecycle dropdown.
- **Infinite scroll:** `phx-viewport-bottom={!@end? && "load_more"}` on the stream `<ul>` (with a
  throttle). `handle_event("load_more", …)` fetches the next page via `load_page(..., @cursor)`,
  `stream(:rows, page, at: -1)`, updates `:cursor`/`:end?`.
- **Reset on change:** `set_scope` / `set_status` / `set_sort` / `search` recompute the first page,
  `stream(:rows, page, reset: true)`, reset `:cursor`/`:end?`/`:empty?`, then `DashboardFilter.persist`.
  When lifecycle changes away from `:live` while `sort == :urgency`, the effective sort becomes
  `:due_asc` (option hidden); the persisted value may stay `urgency` but never applies off-Live.
- **Empty state:** rendered as a sibling of the stream `<ul>`, shown when `@empty?`.

### 5. Migration — indexes for keyset

Add composite indexes to keep keyset pages efficient under the status filters:

- Partial index `(entity_id, due_by, id) WHERE completed_at IS NOT NULL` (Completed).
- Partial index `(entity_id, due_by, id) WHERE closed_at IS NOT NULL` (Skipped).
- `(entity_id, due_by, id)` for Live/All due-ordered scans (the existing partial live unique index
  covers liveness; this supports ordering).
- Title sort index `(entity_id, lower(title), id)` is **optional** for v1 (title sort is infrequent);
  decide in the plan based on expected volume.

Exact index set is finalized in the implementation plan's migration step.

## Components and boundaries

- `Argus.Obligations.list_obligations_page/2` — pure data: SQL filter + sort + keyset page. Testable
  with fixtures, no LiveView.
- `Argus.Obligations.Pagination` (small helper, or inline) — cursor encode/decode + keyset `where`.
- `ArgusWeb.DashboardFilter` — adds `sort` to the persisted entry; unchanged storage/transport.
- `ArgusWeb.ObligationLive.IndexHelpers` — row building, the urgency-window exception, `sorts/1`.
- `DashboardLive.Index` / `MobileLive.Dashboard` — streams, sort control, viewport pagination.
- `MobileLive.Components.obligation_card` — gains `id` attr.

## Error handling

- Invalid `sort` (URL tampering / stale persisted value) → normalized to `:due_asc` at parse time;
  the render path never sees an unknown sort.
- Invalid/garbled `cursor` → treated as "first page" (`nil`); never crashes a mount.
- `urgency` requested on a non-live lifecycle → resolved to `:due_asc` before the query.
- `list_obligations_page/2` raises on an unknown `status` (existing `@status_filters` guard kept).

## Testing (TDD)

**Context — `list_obligations_page/2`:**
- Each sort preset orders correctly (`due_asc`, `due_desc`, `title` case-insensitive).
- Keyset paging: page 1 then page 2 via cursor returns the next slice with no overlap/gap; `end?`
  true on the last page; page size capped at 25.
- SQL search filter matches title / type name / assignee email / literal "unassigned".
- `urgency` status non-live resolves to `due_asc`.

**`DashboardFilter`:**
- `sort` round-trips; defaults to `due_asc`; rejects bogus values; persists in the entry.

**`IndexHelpers`:**
- Urgency+Live: rows within the 1-year window sorted by urgency rank then `due_by`; tail (>1yr)
  appended in `due_by` order, all `:ok`.
- `sorts/1`: includes `urgency` only for `:live`.

**LiveView (Desktop + Mobile):**
- Sort `<select>` reorders the list; choice survives a remount (persistence).
- "Most urgent" option present on Live, absent on Completed/Skipped/All.
- First page caps at 25; `load_more` (viewport) reveals the next slice; `end?` hides the sentinel.
- Empty state renders via `@empty?`.
- Existing DOM ids (`obligation-row-#{id}`, `m-ob-#{id}`) preserved under streams.

## Out of scope

- A "Recently done" sort preset (rejected; non-live defaults to `due_asc`).
- Type/assignee sort dimensions (not requested).
- Sorting urgency in SQL / a materialized urgency column.
- `phx-viewport-top` / bidirectional windowing (we only append forward).
