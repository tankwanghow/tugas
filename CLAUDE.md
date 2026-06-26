# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

Argus is **built**: the Phoenix app is generated and the full 21-task implementation plan has
been executed (contexts, schemas, auth/scope, dual Desktop+Mobile LiveViews, dashboard urgency,
obligation workflow/recurrence, types & membership management, audit, uploads). A post-v1
**Quick Todos** feature (entity-scoped team todos with audit trail, 48h delete window, cancel,
escalate-to-duty, and paginated Desktop+Mobile UIs) has also shipped — see the Quick Todos section
below. `mix precommit` passes. What remains is the plan's two **manual smoke tests** (Desktop and
Mobile happy-paths via `mix phx.server`) and any future enhancements beyond v1 scope.

- **Spec:** `docs/superpowers/specs/2026-06-13-argus-design.md` — authoritative for data model, roles, and workflows.
- **Plan:** `docs/superpowers/plans/2026-06-13-argus-implementation.md` — 21 phased, TDD, commit-per-task steps (all complete).

When extending the app, follow the `argus-conventions` skill and keep the TDD/commit-per-change
rhythm; run `mix precommit` before declaring work done.

## House conventions (read first)

Argus follows the conventions of the sibling Phoenix apps in `~/Projects/elixir` — primarily
**peggy** (UI, magic-link onboarding, request scope, Desktop/Mobile dual interface) and
**full_circle** (context & authorization shape). The authoritative, detailed convention guide is
the **`argus-conventions` skill** (`.claude/skills/argus-conventions.md`) — consult it before
writing non-trivial code. Peggy's full Phoenix 1.8 ruleset (`~/Projects/elixir/peggy/AGENTS.md`)
applies here too. Headlines:

- **Tailwind v4 + daisyUI 5** (no `tailwind.config.js`; daisyUI component classes). App is
  generated **with assets and mailer** — not `--no-assets`/`--no-mailer`.
- **Magic-link-first onboarding, password fallback** (peggy / `phx.gen.auth` 1.8): register with
  email → emailed login link → confirm → land on entity create/select. Login also accepts an
  email+password (fallback) once a user sets a password in settings; `hashed_password` stays
  nullable. A `%Argus.Accounts.Scope{user, entity, membership, role}` struct flows as
  `@current_scope`; never `@current_user`/`@current_role` in templates.
- **Dual UI:** Desktop `/entities/:entity_slug/...`, Mobile `/m/:entity_slug/...`, with an
  `AutoRouteByDevice` plug (mobile-capable tails: `""`, `/obligations/new`, `/obligation-types`,
  `/todos`, `/todos/new`, plus the `/obligations/:id` show + `/invite-session/:role` regexes) + a
  `argus_view` cookie override. Separate LiveViews + layouts (`Layouts.app/1` navbar — desktop nav is
  **💼 Duties · 📑 Todos · 🏷️ Types**; `Layouts.mobile_app/1` bottom-nav shell — five-tab bottom nav is
  **✚ Todo · 📑 Todos · ✚ Duty · 💼 Duties · ☰ More** (the ✚ Duty tab routes to obligation
  create; everything past the five tabs lives in the More sheet). New-obligation has both Desktop
  (`ObligationLive.Form`) and Mobile (`MobileLive.ObligationForm`) LiveViews sharing all non-render
  logic via `ObligationLive.CreateForm` (`load_form`/`validate`/`save` with a redirect-path fn).
  **There is no separate obligation index page** — the **dashboard is the obligation list** on both
  UIs (`DashboardLive.Index` at `/entities/:slug`, `MobileLive.Dashboard` at `/m/:slug`). It's a
  flat, filtered, **server-paginated** list (scope/status/sort controls + search), not a grouped
  view; both render rows as LiveView **streams** built by `ObligationLive.IndexHelpers.load_page/7`
  (role-based default, urgency, tier, event meta), keyset-paged via a `phx-viewport-bottom` sentinel
  (see the dashboard filter/sort section below). Each card shows the **current (latest) event** via the shared
  `ArgusWeb.EventMeta.event_meta/1` component (status badge, count, actor, note). The card's urgency
  **countdown badge** is the only relative-due indicator — there is no separate "due in N days" text.
  After create/complete/skip/end-series, forms and show redirect back to the dashboard.
- **Shell-Escape contract:** both layout shells (`#argus-shell`) bind
  `phx-window-keydown="close_modal_on_escape"`, so **every** LiveView rendered in them must define a
  `handle_event("close_modal_on_escape", …)` clause (no-op if the page has no modals) or it crashes
  on Escape. `ModalEscape.close_obligation_modals/2` is the shared closer for obligation pages
  (handles the document/done/progress/skip/correct/edit modals **and** `editing_note_id` note
  editing); `ModalEscape.close_type_modal/1` closes the type editor, and
  `ModalEscape.close_todo_modal/1` closes the todo edit + cancel modals (used by the todo
  LiveViews). Team-log pages have no modals, so their `close_modal_on_escape` is a no-op.
- LiveView: `to_form` + `<.form>`/`<.input>`, `<.icon name="hero-...">`, streams (never append),
  colocated hooks. Unauthorized context calls return **`:not_authorise`**.
- Run `mix precommit` before declaring work done.

## Commands (post-bootstrap)

```bash
~/Projects/elixir/.global_assets/setup.sh   # once: fetch shared esbuild/tailwind/heroicons binaries
mix setup                             # deps.get + ecto.setup + assets.setup + assets.build
mix phx.server                        # run app (localhost:4000)
mix test                              # full suite (auto creates/migrates test DB)
mix test test/argus/obligations_test.exs            # single file
mix test test/argus/obligations_test.exs:42         # single test by line
mix precommit                         # compile --warnings-as-errors, deps.unlock --unused, format, test
```

**Shared toolchain:** assets (esbuild 0.28.1, tailwindcss 4.3.1, heroicons v2.2.0) are pinned once
under `~/Projects/elixir/.global_assets` and wired in via `~/Projects/elixir/shared_config` — the
same setup every sibling project uses. `config/config.exs` imports `shared_config/assets.exs` and
`mix.exs` resolves heroicons through `WorkspaceAssets`; both fall back to standalone installs if
the workspace dirs are absent. Toolchain versions come from `~/Projects/elixir/mise.toml`.

Tech stack: Elixir 1.19 / OTP 28, Phoenix 1.8.5, LiveView 1.2.1, Ecto 3.13, PostgreSQL (citext), Tailwind v4 + daisyUI 5, Swoosh mailer (magic-link login), Req.

## Architecture

Phoenix LiveView monolith, PostgreSQL, **binary_id (UUID) primary keys everywhere** via the
`Argus.Schema` macro (`use Argus.Schema`). No background jobs, no REST API, no notification
system in v1.

### Multi-tenancy & scope

Tenants are **entities**. Desktop routes are scoped `/entities/:entity_slug/...`, mobile
`/m/:entity_slug/...`. An entity-scoped `live_session` `on_mount` resolves the slug, verifies the
user's membership, and builds a `%Argus.Accounts.Scope{user, entity, membership, role}` exposed as
`@current_scope` (peggy pattern — replaces a standalone plug + ad-hoc `active_entity`/`membership`
assigns). Contexts take `scope`/`current_scope` as their first argument; authorization keys off
`scope.role`, never a global user attribute.

- `Argus.Accounts` — users (email + **magic-link login tokens**; optional password; locale;
  **no timezone on users**), `Scope` struct, `register_user/1`, `deliver_login_instructions/2`.
- `Argus.Entities` — entities (soft-deleted via `deleted_at`; all lookups filter `deleted_at IS NULL`), memberships `(user_id, entity_id, role)`, invitations. One default entity per user (partial unique index). `create_entity/2` also inserts the creator's `admin` membership. `seat_limit` is enforced via a single `seats_available?/1` gate on invite **and** accept **and** direct add.
- `Argus.Authorization` — **scope-first**: `can?(scope, action)` / `can?(scope, action, obligation)`. Keys off the pre-resolved `scope.role` (no per-call DB lookup). Single source of truth for role rules; see the role table below. Unauthorized mutations return `:not_authorise`.
- `Argus.Todos` — **quick todos**: lightweight, entity-scoped, team-visible tasks separate from obligations (see the Quick Todos section below). Scope-first like every other context; unauthorized calls return `:not_authorise`.

### Roles

| Role | Can |
|------|-----|
| admin | everything |
| manager | create/edit obligations, manage types, mark Done on **any** obligation, **skip** a cycle (close without completing; spawns successor when recurring), **end series**, **mark completed-in-error** (spawn replacement) |
| member | view assigned work, add notes/docs while in progress, mark Done **only if primary assignee** |

Collaborators (join table) can move an obligation to `in_progress` and add notes/docs, but
**cannot** mark Done. Only the **primary assignee** or a manager/admin marks Done.

The role table above governs **obligations**. **Todos are flat:** every role (member/manager/admin)
can view, create, edit, complete/reopen, delete, and cancel todos (`@todo_actions` in
`Argus.Authorization`). The one gated todo action is **escalate-to-duty**, which requires
`can?(scope, :create_obligation)` (manager/admin) since it creates an obligation.

**Obligations may be unassigned.** `primary_assignee_id` is **nullable** — an obligation can be
created without a primary assignee and assigned later (`Obligations.list_unassigned/1` surfaces
these; the title search matches the literal `"unassigned"`). An unassigned cycle has **no member
who can mark it Done** — only a manager/admin can (or after a primary assignee is set). The
`mark_done` / `start_progress` authorization checks guard `nil` before comparing
`primary_assignee_id` to the user.

**Every state transition requires a note.** Creating an obligation (the `open_note`),
`start_progress`, **skip**, and end-series all reject a blank note via
`validate_action_note`. The Done note is likewise **always required** (see rule 1). Notes are no
longer optional context — treat them as mandatory on every write that produces an `Event`.

**Skip** (`Obligations.skip/3`, manager/admin) is the unified close-without-completing action: it
stamps `closed_at` on the cycle, writes a `skipped` event, and — if the type is recurring and the
series is not ended — requires `next_due_by` and spawns the next cycle (mirroring the Done→spawn
path). For a one-off cycle (or an already-ended series), it just closes the cycle with no
successor. This action replaced the former `cancel_obligation/3` and `skip_cycle/3` functions.

### Obligations domain — the core model (read the spec before editing)

The single most important design decision: **one `Obligation` row per cycle**, not a standing
series with a rolling `due_by`. A recurrence chain is linked by a shared `series_id` (UUID).

- `Argus.Obligations.Obligation` — one cycle. There is **no `status` string column**; terminal state is expressed via timestamps. A cycle is **live** while `completed_at IS NULL AND closed_at IS NULL` — that's the set dashboards show and that can be worked/completed/skipped. Done stamps `completed_at`; Skip stamps `closed_at` (writes a `skipped` event); End series stamps `closed_at` + `series_ended_at` (writes a `series_ended` event). "Who performed" each terminal action is on the terminal event's `status_by_id` — there are no `done_by`/`skipped_by` columns. This liveness predicate is defined **once** as `Obligations.live/1` (a composable query builder) and every list/dashboard/report composes it — never hand-write it. A partial unique index on `series_id` (where live) enforces **one live cycle per series**. `series_ended_at` (when set) blocks future spawning. The row also **snapshots** `complete_documents` from the type at creation (see rule 1). `primary_assignee_id` is **nullable** (unassigned obligations). **Title is capped at 60 chars** (`validate_length` on the changeset; the UI uses the `char_count_input` component with a live "characters left" counter). The completed-in-error columns — `completed_in_error_at`/`_by_id`/`_reason`, plus self-referential `replaces_id`/`replaced_by_id` FKs — link a wrongly-completed cycle to its replacement (see rule 4).
- `Argus.Obligations.Event` (`obligation_events`) — **append-only** status steps shaped `open → in_progress* → done | skipped | series_ended`. New status = new row; rows are never deleted and status is never rewritten. The step `note` lives here (open context, each progress note, done comment, skip/end-series reason). **`open` is singular** (one per cycle, created at creation) and the terminal event singular (created at completion/skip/end-series), but **`in_progress` may repeat** — every *Update progress* appends another logged `in_progress` event. `start_progress`'s guard (`ensure_progressable`) only rejects a cycle whose terminal event exists — i.e. `event.status in Event.terminal_statuses/0` (= `["done","skipped","series_ended"]`) — with `{:error, :not_live}`; it no longer blocks an already-in-progress cycle.
- `Argus.Obligations.EventDocument` — file uploads attached to an event; the per-file column is **`file`** (a `%{filename, original, path}` map), not `documents`. A live file may be hard-**deleted within 48h** (`document_deletable?`); after that (or for admin-on-locked-cycle) it is **voided** (`voided_at`/`voided_by_id`/`void_reason`) — voided files are kept for audit and **remain downloadable**. `document_slot` matches a name in the obligation's snapshotted `complete_documents` for Done validation, and is **immutable after upload** — there is no Replace and no slot-editing; to change a slot's file, delete/void it and re-upload (uploading is only offered for an unsatisfied slot). A document is classified **required** when its `document_slot` is in the obligation's current snapshot `complete_documents`, otherwise **supporting** (no slot, or a slot no longer in the set).
- `Argus.Obligations.AuditLog` — field-level before/after for **corrections** (title, due_by, assignee, note edits).
- `Argus.Obligations.Type` — **per-entity only** (`entity_id` is **NOT NULL**). There are no
  global system presets; instead, when an entity is created, `Argus.Obligations.SampleTypes`
  seeds a private copy of the sample types into that entity (`seed_for_entity/1`, run inside the
  `create_entity` `Ecto.Multi`). Every entity therefore owns and can edit its full type set —
  `list_types`/`get_type!` filter strictly by `entity_id`, and there is no "immutable preset"
  case any more.

### Documents UI — two surfaces

The obligation Documents UI is split by what a file is **for**, with each file shown
in exactly one place (no duplication):

- **Completion Documents** (`ObligationCompletionDocuments`) — **cycle-level**, one
  modal per obligation: a row per required slot (live file inline, or an inline
  uploader if unsatisfied) plus a voided-required section. Slot uploads attach to the
  cycle's current workable event (`DocumentHelpers.upload_event/1`: `in_progress`
  else `open`). The obligation summary shows each required slot beside the title with
  its live filename; **clicking the slot name opens this modal** (there is no separate
  "Completion documents" button). The modal's Void button is hidden once the cycle is
  no longer live.
- **Step Files** (`ObligationStepFiles`) — **per-step**, a modal per timeline event:
  that step's supporting (no-slot/stale-slot) files + a voided-other section + an
  additional-file uploader.

Classification and partitioning live in `ArgusWeb.ObligationLive.DocumentHelpers`
(`completion_view/2`, `step_files/2`, `parse_slots/1`). When an admin edits a type's
`complete_documents`, `propagate_complete_documents_to_live/3` updates **live**
obligations' snapshot only (completed/closed cycles stay frozen); a file whose slot was
removed/renamed is thereby **reclassified** required → supporting (no row mutation, so
re-adding the slot re-links it). **The create form has no file upload** — a duty is
created with fields only; files are attached afterward from the duty page (completion
documents / step files). The old `ObligationDocumentUpload`/`ObligationDocumentList`
components were removed.

**Upload mechanism — plain HTTP, not LiveView socket upload.** Documents are
**not** uploaded over the LiveView channel (no `allow_upload`/`live_file_input`).
A long mobile camera/file pick backgrounds the page, times out the socket, and
remounts on return — which discarded any in-flight socket upload, regardless of
size. Instead, each "Choose file" button (`ArgusWeb.UploadSlotControls`) runs the
**`UploadDirect`** client hook (`assets/js/upload_direct.js`): it opens a
**transient `<input type=file>` created in `document.body`** (outside LiveView's
managed DOM, so a remount can't destroy the selection), validates size + downscales
images **client-side** (resize *before* the limit check; image detected by
extension **or** MIME type), then `XHR`-POSTs the file to
`ArgusWeb.DocumentController.create/2`
(`POST /entities/:entity_slug/obligations/:obligation_id/documents`, device-agnostic
— mobile pages post the same `/entities/...` path). The controller rebuilds the full
`Scope` and is **server-authoritative** on per-kind size limits
(`Argus.Uploads.Limits`); a plain HTTP request survives backgrounding. On success
the hook pushes `document_uploaded` (both show LiveViews `reload`) or reloads if the
socket is down. The endpoint's `Plug.Parsers` multipart `:length` is raised to 30 MB
(above the 20 MB max). Per-slot errors are shown client-side (inline error row), and
modal + slot-error state survive a reconnect via `UploadUiPersist` (sessionStorage).
`Argus.Obligations.add_document/5` remains the context entry point.

### Three rules that are easy to get wrong

1. **Done validation is enforced only on Done**, never earlier. A Done **note is always
   required** (blank ⇒ `{:error, :note_required}`) — this is unconditional and no longer
   type-configurable (`complete_note_required` has been removed from both the type and the
   obligation snapshot). The only **snapshotted** completion rule is `complete_documents` (copied
   from the type at creation), validated against the obligation's snapshot, **not the live type**
   — editing a type must not retroactively move the bar for a live cycle (type-definition audit is
   out of scope). `complete_documents` (comma-delimited slot names) → one **non-voided** document
   per named slot, counted across **all events in the cycle** (open/in_progress/done), so
   incremental uploads count. Each spawned cycle re-snapshots from the type. See
   `Obligations.Completion`. **Only the completion contract is frozen** — `reminder_offsets`
   (display) and `recurring_interval` (shape of the next cycle) are read **live** from the type by
   design; see the snapshot-vs-live note in the spec.

2. **Recurrence on Done.** Done is a **guarded close**: a conditional `update_all` stamps
   `completed_at` only `WHERE completed_at IS NULL` — 0 rows updated ⇒ `{:error, :not_live}`,
   making Done idempotent and concurrency-safe. If `Recurrence.recurring?(type)` (interval ≠
   `none`) **and** the series is not ended, `next_due_by` is **required** (missing ⇒
   `{:error, :next_due_required}`) and a **new** Obligation is spawned with the same `series_id`,
   type, title, and assignees. Requiring next_due_by is deliberate — it stops a series from
   landing in a "no live cycle, not ended" limbo; to finish without a successor, **End series**.
   The 8 intervals live in `Obligations.Recurrence`; fixed intervals pre-fill the next `due_by`
   (`Recurrence.next_due_suggestion/2`), `custom` returns `nil` (blank picker), `none` is not
   recurring. Interval naming is deliberate: `every_two_weeks` (not bi_weekly), `semiannual`,
   `annual`. `shift_month/2` must clamp end-of-month (Jan 31 + 1mo → Feb 28).

3. **Corrections lock once a cycle is no longer live.** While a cycle is live (`completed_at IS NULL AND closed_at IS NULL`): managers/admins edit obligation fields; note authors edit their own note within **48 hours** (manager/admin override anytime while live). After the cycle is Done or closed (skipped / series-ended) everything is locked except admin-only void-with-reason. Every correction is logged in `AuditLog`.

4. **Completed-in-error is a stamp, not a revert.** `Obligations.mark_completed_in_error/3`
   (manager/admin) **never** clears `completed_at` on the wrong cycle — it stamps
   `completed_in_error_at/_by_id/_reason`, writes an `AuditLog` row (field `"completed_in_error"`),
   and **spawns a standalone one-off replacement** to redo the work, cross-linked via
   `replaced_by_id`/`replaces_id`. The replacement gets a **fresh `series_id` with `series_ended_at`
   set at creation**, so completing it returns `{:ok, completed, nil}` (no spawn, no `next_due`
   required) **even for a recurring type** — and because it's a separate series, a recurring
   original's auto-spawned successor is untouched (Policy A). Guard `validate_correctable/1`:
   must be completed (`completed_at` set), not closed (`closed_at` nil), not already corrected. No uncomplete and
   no new event on the wrong cycle (the event FSM stays forward-only).

### Dashboard = the attention surface

There is intentionally **no notification system** (no bell, no email/SMS, no Oban). The
dashboard is where overdue/due-soon work surfaces, computed at render time:

- `Obligations.Urgency.classify(type, due_by, today)` → `:overdue | :due_soon | :ok`, where
  `:due_soon` means `due_by` is within any offset in the type's `reminder_offsets`
  (comma-delimited days, e.g. `"30,7,1"`). `today` is **required and computed in the entity's
  timezone** via `Urgency.today_for(entity.timezone)` — never `Date.utc_today()`, which would
  mis-date non-UTC tenants near midnight. Used to **sort** the live list (overdue → due_soon → due_by).
- `Obligations.Urgency.tier(type, due_by, today)` → `:overdue | :critical | :due_soon | :approaching
  | :ok` is the **graded** refinement used for **color-coding card borders**. It splits the span
  between the smallest and largest `reminder_offset` into three equal bands (critical → due_soon →
  approaching); `:overdue` (past due) and `:ok` (beyond the largest offset) are fixed endpoints. A
  **single offset** is widened by 7 days so it still yields three bands. Only `min`/`max` drive the
  bands — intermediate offsets are decorative. Rendered by `ArgusWeb.UrgencyBadge`: `tier_border/1`
  (the shared left-accent class `error → error/60 → warning → warning/40 → transparent`, used by
  the desktop dashboard rows and the mobile card so they don't drift) and `urgency_badge/1` (a
  **tier-coloured countdown badge** — "Nd overdue" / "Due today" / "Nd left", nothing when `:ok`).
  Every live row map carries both `urgency` and `tier`.
- `reminder_offsets` / `complete_documents` are validated and normalized on the `Type` changeset
  (write time), so the render path can't crash on bad input; `parse_offsets` still parses defensively.
- Filter (single flat list, no grouping) is **two orthogonal controls** plus a sort and search, not
  a tab strip: a **scope toggle** (`Mine` / `Team`), a **status dropdown** (`Live · Completed ·
  Skipped · All`), and a lifecycle-aware **sort dropdown** (`Due soonest` (default) · `Due latest` ·
  `Someday` · `Title A–Z`, plus `Most urgent` **only on Live**), plus title/type/assignee search.
  `IndexHelpers` keeps `mine?` + `lifecycle` + `sort`; `status_atom/2` maps mine → `my_*`, and
  `effective_sort/2` coerces a sort not offered for the current lifecycle to `:due_asc` (so `urgency`,
  offered only on Live, can't leak to other lifecycles). The controls + search **persist per-entity**
  (`ArgusWeb.DashboardFilter`: ETS store + session snapshot + `POST /session/dashboard-filter`, cleared
  on logout) and survive remounts. The **Skipped** lifecycle selects `closed_at IS NOT NULL` (covers
  both skipped and series-ended cycles; their badges differentiate). Defaults are role-based via
  `default_mine?/1` — members land on **Mine + Live**, managers/admins on **Team + Live**; sort
  defaults to `Due soonest`.
- **Someday = duties with no due date, surfaced by a sort (not a filter).** `due_by` is **nullable**;
  a duty created with the "No due date (Someday)" toggle (a virtual `:someday` changeset field that
  force-nils `due_by` and drops the `due_by` requirement) has `due_by IS NULL`. Dateless duties live
  in their **normal lifecycle list** (Live/Completed/Skipped/All all include them — there is no date
  filtering; the core `live/1` and the older `list_obligations/2` are unchanged). The **`Someday`
  sort** (`apply_page_order(:someday)` → `asc_nulls_first: due_by`) floats no-due-date duties to the
  **top**, then dated ones by due date. Dateless rows carry **no urgency** — `Urgency.classify/tier`
  return `:none` for nil `due_by`, and the dashboards + show pages **guard every date-dependent render
  on `due_by`** (no countdown badge, no tier border, no "due …" text). Date sorts (`due_asc`/`due_desc`)
  use `NULLS LAST` so dateless rows sort to the bottom there. A manager/admin **adds/clears a due date**
  via the edit form's same Someday toggle, through the shared conditional-required changeset.
  **Recurrence requires a date:** `complete`/`skip` only require `next_due_by` / spawn a successor
  when the cycle had a `due_by` (`should_spawn_next?`/`validate_next_due` guard `not is_nil(due_by)`);
  a dateless duty completes as a one-off even for a recurring type, and recurrence resumes if dated.
- **The list is server-paginated, never a full load.** `Obligations.list_obligations_page/2`
  filters (SQL `ILIKE` on title / joined type name / joined assignee email + the literal
  `"unassigned"`), sorts, and pages by **keyset cursor** (sort column + `id`, opaque
  `Obligations.Pagination` codec) for **every** lifecycle. The one in-memory exception is **`Most
  urgent` + `Live`**: `IndexHelpers` ranks a **1-year `due_by` window** in memory (`Urgency.classify`
  needs the entity-tz `today` + type offsets, impractical in SQL — and ranks bare obligations,
  summarising only the sliced page) then continues into a SQL keyset tail (`due_after_or_null`,
  ordered `due_by` asc NULLS LAST) that holds the `>1yr` dated rows **and any dateless duties last**,
  via an opaque two-mode cursor. Both dashboards render **streams** (`phx-update="stream"`, preserved DOM ids) and
  load more via `phx-viewport-bottom="load_more"` (page size 25); `@empty?` drives the empty state,
  `@end?` gates the sentinel. Partial keyset indexes back the Completed/Skipped scans.

### Quick Todos — lightweight team tasks (separate from obligations)

Todos are a deliberately **simpler, parallel domain** to obligations: an entity-scoped, team-visible
checklist for quick tasks that don't warrant a full duty (no type, no assignee, no recurrence, no
documents, no due date / urgency). They live in `Argus.Todos` (`Todo`, `AuditLog`, `Pagination`),
mirror the obligation conventions (scope-first, `Ecto.Multi` writes, `:not_authorise`/`:not_found`
returns, keyset pagination, LiveView streams), and **escalate into** a real obligation when needed.

- **`Argus.Todos.Todo`** — one row per todo (`title` capped at **200** chars). Like obligations,
  **no `status` column** — state is expressed via timestamps and read by predicates:
  `display_status/1` → `:open | :completed | :escalated | :canceled` (priority: escalated → canceled
  → completed → open). `active?/1` is `deleted_at` **and** `canceled_at` **and** `escalated_at` all
  nil; `open?/1` is `active?` and not completed. Soft-delete is `deleted_at`; **canceled** and
  **escalated** are their own terminal stamps (each with `_at`/`_by_id`; escalation also stores
  `escalated_obligation_id`). Completing is **reversible** (toggle re-opens) — `completed_at`/`_by_id`
  flip on/off.
- **Delete vs. Cancel — the 48h window.** A todo is **deletable** (hard soft-delete, hidden
  everywhere) only while **open and within 48h** of creation (`Todo.delete_window_hours`); after 48h
  an open todo can no longer be deleted, only **canceled** — and cancel **requires a note**
  (`validate_action_note`, same rule as obligation transitions). The two are mutually exclusive
  (`deletable?` xor `cancelable?`), so the per-row action menu only ever offers one.
- **Escalate-to-duty.** A manager/admin (`can?(:create_obligation)`) escalates an open todo into an
  obligation: the action navigates to the obligation create form with `?from_todo=<id>`;
  `ObligationLive.CreateForm` pre-fills the title (truncated to the 60-char obligation cap) + an
  `open_note`, and on successful create calls `Todos.record_escalation/3` to stamp the todo
  `escalated_*` and cross-link `escalated_obligation_id`. Escalated todos show a **"View duty"** link.
  `Todos.get_todo_for_escalation/2` guards that the todo is still escalatable (active, not completed).
- **Audit trail.** Every mutation writes a `Todos.AuditLog` row (`created`/`updated`/`completed`/
  `reopened`/`deleted`/`canceled`/`escalated`, with field/old/new for title edits, the cancel note,
  and the obligation id). Per-todo history is inline-expandable on each row; the **team log** pages
  (`TodoLive.TeamLog` desktop, `MobileLive.TodoTeamLog`) show the entity-wide feed via
  `Todos.list_entity_audit_logs/2` rendered by the shared `ArgusWeb.TodoTeamActivity` component.
- **Routes & UI.** Desktop `/entities/:slug/todos` (`TodoLive.Index`) + `/todos/team-log`; mobile
  `/m/:slug/todos` and `/m/:slug/todos/new` (both `MobileLive.Todos`, the `:new` action just patches
  open the create modal) + `/todos/team-log`. **Desktop and mobile share all non-render logic** via
  `ArgusWeb.TodoLive.IndexHelpers` (mount assigns, load/paginate, the modal + action + status
  handlers) and `ActivityFormat`; each LiveView only owns its `render/1` and thin `handle_event`
  delegation — the same Desktop+Mobile split used for obligations. **There is no status filter** —
  the index always renders a single **unified list** (`@list_status = :all` in `IndexHelpers`) so
  open work and history live together and completing/canceling a todo leaves the (now muted) row in
  place rather than making it vanish. That list orders by lifecycle tier (open → completed →
  escalated → canceled), then `inserted_at`/`id`, and is keyset-paged (`list_todos_page/2`, page size
  25, `Todos.Pagination` opaque cursor, composite **tier+timestamp** cursor). The context still
  supports every `status:` (`Todos.parse_status/1`) for `list_todos/2` and tests, but the UI only
  ever requests `:all`. (`limit: :all` is a separate **unbounded** mode that loads everything with no
  cursor — distinct from the `:all` *status* filter.) Rendered as `phx-update="stream"` with a
  `phx-viewport-bottom` sentinel. `list_todos/2` is the non-paginated context API (used by tests).
- **Row animations.** Create/update/delete flash a CSS animation on the row via the `TodoRowEffect`
  colocated hook + `row_effects` assign (cleared on `animationend` → `finish_row_effect`); the
  per-row action `<select>` is driven by the `TodoActionSelect` hook (pushes `todo_action`).
- **Seeding.** `mix argus.seed_todos` seeds sample todos for local/demo use (dev task, not run in
  tests or prod).

### Out of scope for v1

Subjects/client-asset linking (use the obligation title), in-app/email/SMS notifications,
Oban reminder jobs, REST API/mobile, billing beyond `plan`/`seat_limit` fields.

## Conventions

- **TDD per the plan:** write the failing test, watch it fail, implement, watch it pass, commit. One commit per task.
- **Context modules own domain logic.** LiveViews call `Argus.Obligations`, `Argus.Entities`, `Argus.Accounts` — not Repo directly.
- **Multi-step writes use `Ecto.Multi`/transactions** (create obligation + open event; Done + spawn next; skip + event).
- File uploads (v1) go to the local filesystem under a **configurable** `:uploads_dir`
  (`config :argus, :uploads_dir`), laid out `:entity_id/:obligation_id/`; it defaults to the priv
  path in dev but must point at a persistent volume in prod (`:code.priv_dir` is not writable in a
  release). Both **writes and reads** go through the scope-gated `DocumentController`
  (`create/2` for multipart upload, `show/2` for download), never a static route or the LiveView
  socket; it serves voided files too (they stay downloadable for audit). Files are uploaded only
  from the duty page (completion documents / step files), never during create — see the upload
  mechanism note under "Documents UI" above.

## Deployment (Linode + Docker, peggy parity)

Monorepo asset tooling: `~/Projects/elixir/.global_assets/setup.sh` (once), then see
`~/Projects/elixir/shared_config/WORKSPACE_ASSETS.md`. Deploy scripts build from the
**monorepo root** with local esbuild/tailwind/heroicons — no download during `mix assets.deploy`.

Argus ships the **same self-hosted Docker-on-Debian/Linode flow as peggy** (no Fly/Gigalixir).
A two-stage `Dockerfile` builds a Mix release; `mix release` picks up `rel/overlays/bin/server`
(boots with `PHX_SERVER=true`) and `rel/overlays/bin/migrate` (`./argus eval
Argus.Release.migrate`, which runs migrations without Mix inside the container). All
target-specific values live in **`deploy.conf`** (gitignored secrets stay out — `secret.txt`).

```bash
# First-time provision + deploy (prompts for server pwd, DB pwd, SMTP app-password;
# generates SECRET_KEY_BASE). Installs Docker/Nginx/Postgres 17, certbot, builds + ships image.
cd deploy_to_linode && ./launch.sh ../deploy.conf

# Subsequent deploys: rebuild image, stream to server, recreate container, run migrate.
./deploy.sh ../deploy.conf
```

- **`deploy.conf`** keys: `LINODE_IP`, `DB_NAME`/`DB_USER`, `DOCKER_HUB_USERNAME`, `IMAGE_NAME`,
  `DOCKER_CONTAINER_NAME`, `DOMAIN_NAME`, `PORT` (argus uses **8083** to avoid peggy's 8082 if
  co-located), `MAIL_HOST`/`MAIL_PORT`/`MAIL_USERNAME`/`MAIL_FROM`. Passwords + `SECRET_KEY_BASE`
  are prompted/generated at deploy time, never committed.
- **Prod runtime env** (baked into the container by the deploy scripts, read in `runtime.exs`):
  `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, `PORT`, and the SMTP `MAIL_*` vars — **all
  fail-loud** if missing. `:uploads_dir` is set to **`/uploads`**, the host volume
  (`/home/argus/uploads`) mounted into the container by `generate_files_at_server.sh`.
- **Mailer:** prod uses `Swoosh.Adapters.SMTP` (needs `gen_smtp`); the from-address comes from
  `config :argus, :mail_from` (Gmail wants an App Password, not the account password).
- `deploy_to_linode/` scripts are app-agnostic (parameterized by `deploy.conf`) and mirror
  peggy's — keep them in sync when peggy's deploy flow changes.
