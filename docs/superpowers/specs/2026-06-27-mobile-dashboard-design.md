# Mobile dashboard calendar — design

**Date:** 2026-06-27  
**Status:** Approved (pending spec review)  
**Surface:** `MobileLive.Dashboard` (calendar home) + `MobileLive.DutyIndex` (duty list). Desktop
unchanged.

## Problem

Mobile entity home (`/m/:entity_slug`) is still the paginated duty **list** — the same surface
desktop moved to `/entities/:slug/duties` when the desktop **calendar dashboard** shipped at
`/entities/:slug`.

Mobile users lack a calendar overview, Someday strip, and inline todos preview. The bottom nav
also treats the list as “home,” which no longer matches desktop’s attention model.

## Decisions (locked)

| Topic | Decision |
|-------|----------|
| Mobile home | **Calendar dashboard** at `/m/:slug` (replaces list as home) |
| Duty list | **Moved** to `/m/:slug/duties` (`MobileLive.DutyIndex`) — same filters/search/pagination as today |
| Calendar content | **Live duties only**; month grid + Someday strip + todos preview (parity with desktop) |
| Bottom nav | **Context-aware** on three hubs; **Calendar hub (5 tabs)** on all other entity mobile pages |
| Shared logic | Extract dashboard mount/events into `DashboardLive.IndexHelpers`; desktop + mobile LiveViews stay thin |
| Desktop | **No changes** in this iteration |

## Navigation

### Routes

| Destination | Route | Module |
|-------------|-------|--------|
| Calendar (home) | `/m/:slug` | `MobileLive.Dashboard` |
| Duty list | `/m/:slug/duties` | `MobileLive.DutyIndex` (new — extracted from old dashboard) |
| Duty show | `/m/:slug/duties/:id` | `MobileLive.DutyShow` (unchanged) |
| Create duty | `/m/:slug/duties/new` | `MobileLive.DutyForm` (unchanged) |
| Todos | `/m/:slug/todos` | `MobileLive.Todos` (unchanged) |
| Create todo | `/m/:slug/todos/new` | `MobileLive.Todos` `:new` (unchanged) |

- `AutoRouteByDevice` already whitelists `/duties` — desktop `/entities/:slug/duties` ↔ mobile
  `/m/:slug/duties` works without plug changes.
- Mobile UA / cookie default entry remains `/m/:slug` (now calendar).

### Context-aware bottom nav

`Layouts.mobile_app/1` gains `nav_context` (`:calendar` | `:todos` | `:duties`). Default
`:calendar`.

| `nav_context` | Used on | Tabs (left → right) |
|---------------|---------|---------------------|
| `:calendar` | Calendar home **and all other entity mobile pages** | ✚ Todo · 📑 Todos · ✚ Duty · 💼 Duties · ☰ More |
| `:todos` | `/m/:slug/todos` (`:index` only) | ✚ Todo · 💼 Duties · 📅 Calendar · ☰ More |
| `:duties` | `/m/:slug/duties` | 📑 Todos · ✚ Duty · 📅 Calendar · ☰ More |

Tab mapping:

| Slot | Label | Route |
|------|-------|-------|
| ✚ Todo | Todo | `/m/:slug/todos/new` |
| 📑 Todos | Todos | `/m/:slug/todos` |
| ✚ Duty | Duty | `/m/:slug/duties/new` |
| 💼 Duties | Duties | `/m/:slug/duties` |
| 📅 Calendar | Calendar | `/m/:slug` |
| ☰ More | More | opens More sheet (unchanged) |

Implementation sketch — nav sets as data:

```elixir
@nav_sets %{
  calendar: [:new_todo, :todos, :new_duty, :duties, :more],
  todos:    [:new_todo, :duties, :calendar, :more],
  duties:   [:todos, :new_duty, :calendar, :more]
}
```

- 5-tab contexts use `grid-cols-5`; 4-tab contexts use `grid-cols-4`.
- Active tab gets `text-primary`; inactive `text-base-content/60`.
- No “you are here” tab on 4-tab hub pages (current page is omitted from the bar).

**`nav_context` per LiveView:**

| LiveView | `nav_context` |
|----------|---------------|
| `MobileLive.Dashboard` | `:calendar` |
| `MobileLive.DutyIndex` | `:duties` |
| `MobileLive.Todos` `:index` | `:todos` |
| `MobileLive.Todos` `:new` | `:calendar` |
| `MobileLive.DutyForm`, `DutyShow`, `DutyTypes`, `Members`, `TodoTeamLog`, `InviteSession` | `:calendar` |

Replace the old `active` atom (`:duties`, `:todos`, `:new_duty`, …) with `nav_context` across
mobile LiveViews.

## Layout

Single scrollable column inside `Layouts.mobile_app` (no sidebar). Order top → bottom:

```
┌─────────────────────────────────┐
│ Sticky toolbar                  │
│  Mine | Team                    │
│  ‹  June 2026  ›  Today         │
├─────────────────────────────────┤
│ Sun Mon Tue Wed Thu Fri Sat     │
│ [compact month grid]            │
├─────────────────────────────────┤
│ Someday (horizontal scroll)     │
├─────────────────────────────────┤
│ Todos preview                   │
│  open + recently completed      │
└─────────────────────────────────┘
     [context-aware bottom nav]
```

**Sticky toolbar** — same pattern as the current mobile duty list (`sticky top-0 z-30`,
`bg-base-100/95 backdrop-blur`, bottom border). Mine/Team uses `DutiesFilter` persistence.

**Page padding** — `px-4` on scroll body; bottom padding accounts for fixed nav (`pb-10` on shell).

## Calendar behavior

Behavior matches the desktop dashboard (`docs/superpowers/specs/2026-06-27-dashboard-calendar-design.md`)
except where mobile density differs below.

### Month grid (mobile variant)

| Element | Desktop | Mobile |
|---------|---------|--------|
| Cell min-height | `min-h-24` | `min-h-14` |
| Day number | `text-xs` | `text-[10px]` |
| Chips per day before “+N more” | 3 | **2** |
| Chip content | title + type name | **title only** on grid cells |
| Chip text size | `text-xs` | `text-[10px]` |
| Duty link | `/entities/:slug/duties/:id` | `/m/:slug/duties/:id` |

Today ring, out-of-month muting, urgency `tier_border/1` — unchanged.

### Overflow modals

- Day “+N more” and Someday “+N more” use the same modal pattern as desktop.
- Full-width `modal-box` on narrow viewports.
- `close_modal_on_escape` closes day modal, then someday modal (shell contract).

### Someday strip (mobile variant)

- Same Mine/Team scope and title A–Z sort as desktop.
- Chips in a **horizontal scroll row** (`overflow-x-auto flex-nowrap gap-1`) — one line tall.
- Max **6** visible chips before “+N more” (desktop remains 10).
- Section hidden when empty.
- Chips link to `/m/:slug/duties/:id`.

### Scope toggle

- Mine / Team tabs; `DutiesFilter.assign_filters/2` on mount, `DutiesFilter.persist/1` on toggle.
- Maps to `IndexHelpers.status_atom(mine?, :live)`.
- No lifecycle, sort, or search on the calendar (those stay on the duty list page).

## Todos preview

Stacked section below Someday (not a side column):

- **Open:** up to **11** todos (`Todos.list_todos_page(..., status: :open, limit: 11)`).
- **Recently completed:** up to **5** (`status: :completed, limit: 5`).
- Each row: checkbox + truncated title; `TodoRowEffect` hook + `row_effects` assign.
- `toggle_todo_complete` → in-place update + effect; `finish_row_effect` → `load_todos/1` (DB
  backfill — same as desktop).
- No edit, cancel, history, or create on the dashboard preview.
- **“View all →”** links to `/m/:slug/todos`.
- Empty states match desktop copy with mobile paths.
- Open and completed lists each scroll inside `max-h-48` when long (no desktop 2/3 split).

## Architecture

### Modules

| Module | Responsibility |
|--------|----------------|
| `MobileLive.Dashboard` | Calendar home — render + thin `handle_event` delegation |
| `MobileLive.DutyIndex` | Paginated duty list (today’s `MobileLive.Dashboard` list UI + events) |
| `DashboardLive.IndexHelpers` | **New** — shared mount, `load_dashboard/1`, `load_todos/1`, all calendar/todo events |
| `DashboardLive.Index` | Refactor to use `IndexHelpers` (behavior unchanged) |
| `DashboardLive.CalendarHelpers` | Unchanged — month grid, grouping, duty queries |
| `TugasWeb.DutyCalendar` | Add `variant` (`:desktop` default, `:mobile`) — density, chip limits, paths |
| `TugasWeb.DashboardTodosPanel` | Add `variant` — paths, compact mobile layout |
| `TugasWeb.Layouts` | Context-driven `mobile_bottom_nav/1` |

### `IndexHelpers` API (sketch)

```elixir
def mount_dashboard(socket, session)
def handle_set_scope(socket, mine)
def handle_prev_month(socket)
def handle_next_month(socket)
def handle_today(socket)
def handle_open_day_modal(socket, date_iso)
def handle_close_day_modal(socket)
def handle_open_someday_modal(socket)
def handle_close_someday_modal(socket)
def handle_toggle_todo_complete(socket, id)
def handle_finish_row_effect(socket, id)
def handle_close_modal_on_escape(socket)
```

Preview limits live in one module (`@open_preview_limit 11`, `@completed_preview_limit 5`) so
desktop and mobile stay in sync.

### `DutyCalendar` variant attrs

```elixir
attr :variant, :atom, default: :desktop
attr :slug, :string, required: true
# ... existing attrs
```

Variant drives:

- `max_chips_per_day/0` override (2 vs 3) — pass as assign or helper function
- `max_someday_chips/0` override (6 vs 10)
- Cell/chip CSS classes
- `navigate` path prefix (`/entities/` vs `/m/`)

### Data loading

Identical to desktop — see desktop spec “Data loading” section. No new context APIs. Month-bounded
query only (no pagination on calendar).

### LiveView events

Same event names as `DashboardLive.Index` so shared components (`DutyCalendar`, `DashboardTodosPanel`)
work on both surfaces without renaming `phx-click` targets.

## Duty list page (`MobileLive.DutyIndex`)

Extract verbatim from current `MobileLive.Dashboard`:

- Sticky search + lifecycle + Mine/Team + sort toolbar
- Streamed `duty_card` rows + `phx-viewport-bottom` pagination
- All existing events (`set_scope`, `set_status`, `set_sort`, `search`, `load_more`)
- `nav_context={:duties}`
- Page title/header: “Duties” (not “Dashboard”)

No behavior changes — only route and module rename.

## Testing

### `test/tugas_web/live/mobile_live/dashboard_test.exs` (new / rewrite)

1. Renders calendar — month label, 7 headers, `#duty-calendar`.
2. Duty on correct date cell.
3. Overdue chip tier border class.
4. Someday duty in strip, not on grid.
5. Mine/Team scope filtering.
6. Month prev/next/today navigation.
7. Todos preview visible; “View all” links to `/m/.../todos`.
8. Toggle todo complete + `finish_row_effect` moves row to recently completed.
9. Reopen completed todo returns to open list.
10. Completing a todo backfills open preview when more than 11 open todos exist.
11. Day overflow “+N more” opens modal.
12. Someday overflow “+N more” opens modal.

### `test/tugas_web/live/mobile_live/duty_index_test.exs` (new)

Migrate list-specific tests from old mobile dashboard tests (if any) or smoke-test:

- List renders at `/m/:slug/duties`
- Search, scope, lifecycle, sort, load_more still work

### `test/tugas_web/layouts_mobile_nav_test.exs` (or LiveView integration)

- `:calendar` context → 5 tabs with correct `navigate` hrefs
- `:todos` context → 4 tabs (no Todos tab)
- `:duties` context → 4 tabs (no Duties tab)
- Secondary page (e.g. duty show) → `:calendar` 5-tab set

### `test/tugas_web/plugs/auto_route_by_device_test.exs`

- Assert `/entities/:slug/duties` redirects to `/m/:slug/duties` on mobile UA

Run `mix precommit` before declaring done.

## Out of scope

- Desktop dashboard or `DutyLive.Index` changes
- Week/agenda view or alternate calendar layouts
- Todos preview on the duty list page
- Changing More sheet contents (except any link that still pointed at list-as-home)
- Push notifications, widgets, offline mode
- Search/lifecycle filters on the calendar page

## Implementation notes

- Follow TDD: failing test → implement → `mix precommit`.
- Prefer one commit per logical task when using a phased plan.
- `close_modal_on_escape` required on every `mobile_app` LiveView (shell contract).
- Refactor desktop `DashboardLive.Index` to `IndexHelpers` **first** so mobile reuses tested logic.