# Someday as an orthogonal "Due date" filter — design

**Date:** 2026-06-23
**Status:** Approved (pending spec review)
**Supersedes the filter surface of:** `2026-06-23-someday-no-due-date-duties-design.md` (Someday was
built as a *lifecycle* value; this makes it an orthogonal filter). All other parts of that feature
(nullable `due_by`, create/edit Someday toggle, recurrence guard, urgency `:none`, render guards,
show pages, promotion/demotion) are **unchanged**.

## Problem

Someday is currently a **lifecycle** option (`Live · Someday · Completed · Skipped · All`), where
Someday = live `AND due_by IS NULL`. Because it is welded to "live," you cannot view *completed* (or
skipped) dateless duties as their own set. "Dateless-ness" is orthogonal to lifecycle and should be
its own filter, so `lifecycle=Completed × Someday`, `lifecycle=Live × Someday`, etc. are all
expressible.

## Decision (locked)

- Add an orthogonal **`date_filter`** dimension: `dated | someday | all_dates`, default **`dated`**.
  - `dated` → `due_by IS NOT NULL`
  - `someday` → `due_by IS NULL`
  - `all_dates` → no `due_by` constraint
- **Remove `someday` from the lifecycle vocabulary.** Lifecycle reverts to `live · completed ·
  skipped · all`. The core `live/1` predicate stays as-is.
- Lifecycle and `date_filter` **compose**: lifecycle picks the status set; `date_filter` narrows by
  `due_by` presence. So `Live × dated` = today's deadline list (the default view, unchanged
  behaviour); `Completed × someday` = completed dateless duties; etc.
- UI: a fourth control — a **"Due date"** dropdown (`Has due date` *(default)* · `Someday` ·
  `All dates`) — beside the lifecycle dropdown on both dashboards.

## Architecture

### 1. Query — `Argus.Obligations.list_obligations_page/2`

**Revert** the Someday-as-lifecycle pieces added previously:
- `@status_filters` → back to `~w(my_live my_completed my_skipped my_all live completed skipped all)a`
  (drop `:someday`/`:my_someday`).
- Remove the `apply_status_filter(:someday/:my_someday)` clause.
- Remove `apply_page_status/2` (the `:live`-narrowing helper); `list_obligations_page` calls
  `apply_status_filter/2` directly again.
- Remove `:my_someday` from the `scope_to_assignee/3` guard list.

**Add** an orthogonal date scope, applied after the status filter:
- New `:date_scope` option (`:dated | :someday | :all_dates`, default `:dated`), validated.
- `apply_date_scope(query, :dated) -> where(not is_nil(due_by))`;
  `apply_date_scope(query, :someday) -> where(is_nil(due_by))`;
  `apply_date_scope(query, :all_dates) -> query`.
- Pipeline: `… |> apply_status_filter(status) |> apply_date_scope(date_scope) |> apply_search(…) |>
  apply_page_order(sort) |> apply_page_cursor(…)`.

**Keep** (still needed): the NULLS-LAST nullable-`due_by` keyset (`asc_nulls_last`/`desc_nulls_last`,
null-marker cursor) for date sorts under `all_dates`, and the `:recent` sort.

### 2. Sort availability — `IndexHelpers`

Available sorts depend on **(lifecycle × date_filter)**:

| Sort | Offered when |
|------|--------------|
| Most urgent (`urgency`) | `lifecycle == :live AND date_filter == :dated` (pure deadline list — keeps the in-memory urgency-window path seeing only dated rows) |
| Recently added (`recent`) | `date_filter == :someday` (dateless ⇒ recency; the default there) |
| Due soonest / latest (`due_asc`/`due_desc`) | `date_filter in [:dated, :all_dates]` |
| Title A–Z (`title`) | always |

- `sorts(lifecycle, date_filter) :: [{value, label}]` (was `sorts/1`).
- `default_sort(lifecycle, date_filter)`: `:someday → :recent`, else `:due_asc`.
- `effective_sort(sort, lifecycle, date_filter)`: keep `sort` if it's in `sorts(lifecycle,
  date_filter)`'s values, else `default_sort(lifecycle, date_filter)`.
- `parse_sort` keeps `recent`/`urgency`/`due_*`/`title` (unchanged).
- `sorts(:someday)`-style lifecycle-only clauses are removed; `@lifecycles` drops `:someday`;
  `lifecycle_label(:someday)`, `parse_lifecycle("someday")`, `status_atom(_, :someday)`,
  `empty_message(_, :someday)` are removed.
- **New `date_filter` vocabulary** in `IndexHelpers`: `date_filters/0` → `[{"dated","Has due date"},
  {"someday","Someday"},{"all_dates","All dates"}]`; `parse_date_filter("someday") -> :someday`,
  `("all_dates") -> :all_dates`, `(_) -> :dated`.
- `empty_message(mine?, lifecycle, date_filter)`: `date_filter == :someday` →
  `"No someday duties#{who}."`; otherwise the existing lifecycle-based message.

### 3. Page loader — `IndexHelpers.load_page`

Signature gains `date_filter`:
`load_page(scope, today, mine?, lifecycle, date_filter, query, sort, cursor) :: %{rows, cursor, end?}`.
- `eff = effective_sort(sort, lifecycle, date_filter)`; `status = status_atom(mine?, lifecycle)`.
- Non-urgency: `list_obligations_page(scope, status: status, date_scope: date_filter, query: query,
  sort: eff, cursor: cursor)`.
- Urgency (`eff == :urgency`, which only occurs for `live × dated`): the existing in-memory
  window+tail path, calling `list_obligations_page` with `date_scope: :dated` (the window's
  `due_before` already excludes nulls). No change to the window/tail logic itself.

### 4. Persistence — `ArgusWeb.DashboardFilter`

- `@lifecycles` → `~w(live completed skipped all)` (drop `someday`).
- Add `@date_filters ~w(dated someday all_dates)`.
- The per-entity entry gains `"date_filter"` (default `"dated"`, bogus → `"dated"`), threaded through
  `session_entry`, `current_entry`, `merge_saved`, `defaults`, `assign_filters` (assigns
  `:date_filter`), and the `store-dashboard-filter` push payload. `parse_date_filter`/`param_date_filter`
  mirror the existing `sort` helpers.

### 5. Dashboards — `DashboardLive.Index` / `MobileLive.Dashboard`

- Lifecycle `<select>` renders `Live · Completed · Skipped · All` (Someday gone, via reverted
  `IndexHelpers.lifecycles/0`).
- New **"Due date"** `<select>` (`#obligation-date-filter` / `#m-obligation-date-filter`,
  `phx-change="set_date_filter"`, options from `Index.date_filters/0`), placed beside the lifecycle
  dropdown (desktop toolbar; mobile — fit into the existing header control row next to status/sort).
- Sort `<select>` options now come from `Index.sorts(@lifecycle, @date_filter)`.
- New `handle_event("set_date_filter", %{"date_filter" => v}, …)`: assign `:date_filter`,
  `load_first_page`, `DashboardFilter.persist`. The four existing mutating handlers
  (`set_scope`/`set_status`/`set_sort`/`search`) and `load_first_page`/`load_more` thread
  `@date_filter` into `load_page`.
- `@date_filter` assigned on mount via `DashboardFilter.assign_filters`.
- Row rendering is **unchanged** (dateless rows already hide due/urgency chrome).

## Error handling

- Invalid `date_filter` (URL/stale) → `:dated`.
- A persisted sort not valid for the current `(lifecycle, date_filter)` → coerced by
  `effective_sort/3` (e.g. `urgency` selected, then user switches date_filter to `someday` →
  becomes `recent`).
- `:date_scope` validated in `list_obligations_page`; unknown → treated as `:dated` (or raise,
  matching the `status` guard style — pick raise for symmetry with the status guard).

## Testing (TDD)

**Context:**
- `list_obligations_page` with `date_scope: :dated|:someday|:all_dates` filters correctly, composing
  with each lifecycle (esp. `status: :completed, date_scope: :someday` returns completed dateless).
- `:live` no longer excludes dateless on its own (that's now `date_scope: :dated`).
- `all_dates` date-sorted paging still places dateless rows last (NULLS-LAST keyset unchanged).

**IndexHelpers:**
- `sorts(lifecycle, date_filter)`: urgency only for `live×dated`; recent only for `*×someday`; due
  sorts for dated/all; title always.
- `effective_sort/3` coercions; `parse_date_filter`; `empty_message/3` someday text.

**LiveView (desktop + mobile):**
- The Due-date dropdown filters within a lifecycle: `Completed × Someday` shows completed dateless
  duties; `Live × Someday` shows live dateless; default `Live × dated` matches today's deadline list.
- Switching date_filter to Someday changes the offered sorts (urgency/due gone, recent appears) and
  the list; choice persists across remounts.

## Out of scope / unchanged

- Schema (`due_by` nullable), create/edit "No due date" toggle, recurrence date-guard, urgency
  `:none`, dashboard/show render guards, promotion/demotion — all already shipped, untouched.
- A combined cross-entity "All dates" default (we default to `dated`, preserving the deadline view).
