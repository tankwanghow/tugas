# Argus — Multi-Tenant Obligations Tracking System

**Date:** 2026-06-13  
**Status:** Approved for implementation planning

## Overview

Argus is a multi-tenant web application for tracking obligations — regulatory filings, operational renewals, client deliverables, and custom deadlines. Users define obligation types (with system presets), assign work to team members, track progress with notes and documents, and see what needs attention on the dashboard.

**Tech stack:** Phoenix LiveView monolith, PostgreSQL.

## Goals

| Use case | Example |
|----------|---------|
| Regulatory & tax (A) | SSM filings, LHDN, EPF/SOCSO — Malaysia presets |
| Internal ops (B) | License renewals, insurance, equipment maintenance |
| Client SLAs (C) | Audit deadlines, report submissions (title identifies client) |
| General (D) | User-defined obligation types and tasks |

## Tenancy & Authentication

From initial brainstorm (`argus_brainstrom.txt`):

### Users

- `email` (citext), `hashed_password`, `confirmed_at`
- `locale` (default `"en"`)

### Entities (tenants)

- `slug` (citext), `name`, `timezone`, `plan` (default `"free"`), `seat_limit` (default 5)
- Soft delete: `deleted_at`, `deleted_by_id`

### Memberships

- `user_id`, `entity_id`, `role`, `invited_by_id`, `accepted_at`, `is_default`
- Unique `(user_id, entity_id)`; one default entity per user

### Entity Invitations

- `entity_id`, `email`, `role`, `token`, `invited_by_id`, `expires_at`, `accepted_at`
- Pending invite unique per `(entity_id, email)`

## Roles & Permissions

| Role | Permissions |
|------|-------------|
| **admin** | Full control — members, settings, types, obligations, cancel, end series |
| **manager** | Create obligations, manage types, mark Done on any obligation, cancel, end series, edit fields (active cycles) |
| **member** | View assigned work, add notes/documents while in progress, mark Done on assigned obligations (primary only) |

### Assignment

- **Primary assignee** (required) — owner of the obligation
- **Collaborators** (optional, via join table) — can transition to `in_progress` and add notes/documents
- **Done:** primary assignee or manager/admin only (collaborators cannot mark Done)

### Cancel (manager/admin only)

| Action | Effect |
|--------|--------|
| **Cancel obligation** | Current obligation `status → cancelled`; `cancelled` event logged; removed from active dashboards |
| **End series** | Cancel current obligation + set `series_ended_at` on series; blocks future recurrence spawn |

## Data Model

### ObligationType

System presets (`entity_id` null) + per-entity custom types (clone/edit/create).

| Field | Type | Notes |
|-------|------|-------|
| `entity_id` | FK nullable | null = system preset |
| `name` | string | e.g. "EPF Monthly" |
| `recurring_interval` | enum | See [Recurring intervals](#recurring-intervals) |
| `complete_note_required` | boolean | Enforced on Done only |
| `complete_documents` | string | Comma-delimited slot names, e.g. `"statutory_form,payment_receipt"` — one file per name required on Done |
| `reminder_offsets` | string | Comma-delimited days before due, e.g. `"30,7,1"` — drives dashboard urgency badges (not push notifications) |

#### Recurring intervals

Stored as snake_case atoms/strings in code. User-facing labels via Gettext. The interval alone controls recurrence and next-due pre-fill on Done — no separate flag needed.

| Code value | Display label | On Done |
|------------|---------------|---------|
| `none` | One-off | No next obligation spawned |
| `weekly` | Weekly | Prompt; pre-fill `due_by` + 1 week |
| `every_two_weeks` | Every 2 weeks | Prompt; pre-fill `due_by` + 2 weeks |
| `monthly` | Monthly | Prompt; pre-fill `due_by` + 1 month |
| `quarterly` | Quarterly | Prompt; pre-fill `due_by` + 3 months |
| `semiannual` | Every 6 months | Prompt; pre-fill `due_by` + 6 months |
| `annual` | Yearly | Prompt; pre-fill `due_by` + 1 year |
| `custom` | Custom | Prompt; blank date picker (user picks specific date) |

**Naming notes:**

- **`every_two_weeks`** not `bi_weekly` / `biweekly` — "bi-weekly" is ambiguous (every 2 weeks vs twice per week).
- **`semiannual`** not `half_year` / `biannual` — means once every 6 months; "biannual" is often confused with every 2 years.
- **`annual`** not `annually` — enum values read better as adjectives (`:monthly`, `:annual`); labels use full words ("Yearly").
- **`custom`** — recurring, but no fixed formula; always blank date picker.
- **`none`** — implies one-off; no prompt for next due date.

### Obligation

One row **per cycle** (not a standing series with rolling `due_by`).

| Field | Type | Notes |
|-------|------|-------|
| `entity_id` | FK | Tenant scope |
| `obligation_type_id` | FK | |
| `series_id` | UUID | Shared across all cycles in a recurrence chain |
| `title` | string | Required short label (e.g. "HQ License Renewal") |
| `primary_assignee_id` | FK → users | Required |
| `due_by` | date/datetime | Current cycle due date |
| `status` | enum | `active`, `cancelled` |
| `completed_at` | utc_datetime nullable | Set when the Done event is recorded — terminal "closed" marker (the `Obligation.status` stays `active`; "done-ness" is this timestamp, not a status value) |
| `series_ended_at` | utc_datetime nullable | Set by "End series" — blocks future spawn |

A cycle is **live** while `completed_at IS NULL AND status = "active"` — this is the set that
appears on dashboards and can be worked, completed, edited, or cancelled. `completed_at` and
`cancelled` are the two terminal states; both lock the cycle (see [Corrections Model](#corrections-model)).

**One live cycle per series** is enforced by a partial unique index on `series_id` where the
cycle is live — preventing concurrent Done calls from spawning duplicate next cycles.

### obligation_collaborators

| Field | Type |
|-------|------|
| `obligation_id` | FK |
| `user_id` | FK |

Unique `(obligation_id, user_id)`.

### ObligationEvent

One row per workflow step. Grouped by `obligation_id` (one obligation row per cycle).

| Field | Type | Notes |
|-------|------|-------|
| `obligation_id` | FK | |
| `status` | enum | `open`, `in_progress`, `done`, `cancelled` |
| `status_by_id` | FK → users | Who triggered this step |
| `note` | text nullable | Step note — open context, done comment, cancel reason; enforced on Done when `complete_note_required` |
| `inserted_at` | utc_datetime | |

**Append-only status steps** — new statuses are new rows (`open` → `in_progress` → `done`); event rows are not deleted and status is not rewritten.

**Content is correctable** while the obligation cycle is active (see [Corrections Model](#corrections-model)):

- **Notes** — `note` can be edited (typo fixes); changes logged in `ObligationAuditLog`
- **Files** — add new `ObligationEventDocument` rows anytime; wrong files **voided** (not deleted), then re-uploaded

After Done or cancelled, event notes and documents are locked (admin-only void with reason).

### ObligationEventDocument

Multiple per event — incremental file uploads during open / in_progress.

| Field | Type | Notes |
|-------|------|-------|
| `obligation_event_id` | FK | |
| `documents` | attachment ref | File storage TBD (e.g. filesystem, S3) |
| `document_slot` | string nullable | Matches `complete_documents` name on Done validation |
| `user_id` | FK | Who uploaded/wrote |
| `voided_at` | utc_datetime nullable | Wrong upload voided, not deleted |
| `voided_by_id` | FK nullable | |
| `void_reason` | text nullable | |
| `inserted_at` | utc_datetime | |

Voided documents excluded from Done slot validation but retained for audit.

### ObligationAuditLog

Field-level before/after for corrections.

| Field | Type | Notes |
|-------|------|-------|
| `obligation_id` | FK nullable | |
| `obligation_event_id` | FK nullable | For event note edits |
| `field` | string | e.g. `title`, `due_by`, `note`, `primary_assignee` |
| `old_value` | text | |
| `new_value` | text | |
| `user_id` | FK | |
| `inserted_at` | utc_datetime | |

## Workflows

### Create Obligation

1. Manager fills: title, type, primary assignee, optional collaborators, due_by
2. Optional "Notes" on form → saved as `note` on Open event (serves as description/context)
3. System creates `Obligation` (`status: active`, new `series_id`)
4. System creates `ObligationEvent` (`status: open`, optional `note`)

### Work (optional)

While cycle is active (not yet `done`):

- Transition to `in_progress` (one event per cycle)
- Add documents incrementally on the `open` or `in_progress` event (multiple `ObligationEventDocument` rows over time)
- Step-level notes live on `ObligationEvent.note` (open context, done comment, cancel reason)

Note and document requirements on type are **not** enforced until Done — only on Done.

### Done

1. User (primary or manager) triggers Done — only allowed while the cycle is **live**
   (`completed_at IS NULL AND status = "active"`); a guarded transition sets `completed_at`,
   so a second concurrent Done finds no live row and is rejected (idempotent)
2. Enforce `ObligationType` rules:
   - `complete_note_required` → `note` present on Done event
   - `complete_documents` → one non-voided file per named slot
   - **Recurring & series not ended** (`recurring_interval ≠ none AND series_ended_at IS NULL`)
     → `next_due_by` is **required**. Done is rejected without it. This is what guarantees a
     recurring series always has a successor cycle and never lands in a "no live cycle, not
     ended" limbo. To stop recurrence without naming a next date, use **End series** instead.
3. In one transaction: set `Obligation.completed_at`, create `ObligationEvent`
   (`status: done`, `note`) + any Done document uploads
4. If `recurring_interval` is not `none` **and** `series_ended_at IS NULL`:
   - Prompt: "Next due date?" — required (see step 2)
   - Pre-fill from interval formula for fixed intervals (`weekly` … `annual`); blank picker for `custom` (user must pick)
   - Create **new** `Obligation` (same `series_id`, type, title, assignees, collaborators, new `due_by`)
   - Create `ObligationEvent` (`status: open`) on new obligation
5. Completed obligation row is closed via `completed_at` and otherwise unchanged (historical record)

### Cancel

**Cancel obligation** (manager/admin):

- `Obligation.status → cancelled`
- `ObligationEvent` (`status: cancelled`, optional note)
- No Done rules, no next obligation spawned

**End series** (manager/admin):

- Same as cancel obligation
- Set `series_ended_at` on the obligation (or series record keyed by `series_id`)
- Future Done on any obligation in series does not spawn next cycle

## Corrections Model

Lock after Done/cancelled. Edits while cycle is active.

### Obligation fields (`title`, `due_by`, assignees)

| State | Who can edit |
|-------|----------------|
| Active | manager, admin |
| Done / cancelled | locked |

→ Logged in `ObligationAuditLog`.

### Event notes (`ObligationEvent.note`)

| Rule | Detail |
|------|--------|
| Author | Edit own event note within 48 hours (typo fixes) |
| Override | manager/admin anytime before Done |
| After Done / cancelled | locked |

→ Each edit logged in `ObligationAuditLog` (before/after).

### Documents (`ObligationEventDocument`)

Users can **add**, **void**, and **re-upload** files while the cycle is active:

- **Add** — new document row on `open` or `in_progress` event
- **Remove (void)** — uploader voids own file before Done; manager/admin voids any file before Done; row kept for audit (`voided_at`, `voided_by_id`)
- **Replace** — void wrong file, upload new row (same `document_slot` if applicable)

After Done / cancelled: locked (admin-only void with required reason).

### Status steps

Status transitions only move forward (`open` → `in_progress` → `done`). Event rows are not deleted. A wrong status cannot be undone — manager/admin **cancel obligation** instead.

## Dashboard (v1)

Split view with role-aware default tab. **No separate notification system** — the dashboard is the attention surface (users must open the app; overdue and due-soon items are visible here).

| Tab | Content | Default for |
|-----|---------|-------------|
| **My work** | Obligations where user is primary or collaborator; active only; sorted by due date | member |
| **Team overview** | All active upcoming/overdue obligations in entity | manager, admin |

Filter: **live cycles only** — `Obligation.status = active AND completed_at IS NULL`. (Filtering
on `status` alone is insufficient: completed cycles keep `status = active`, so they must be
excluded via `completed_at IS NULL` or they linger on dashboards forever.)

### Urgency badges (from `reminder_offsets`)

Computed at render time from `due_by` vs **today in the entity's timezone** — no background jobs,
no notification records. "Today" is `DateTime.now(entity.timezone)` reduced to a date, **not**
`Date.utc_today()`; otherwise overdue/due-soon flip at the wrong moment near midnight for
non-UTC tenants (e.g. Malaysia, UTC+8).

| Urgency | Rule |
|---------|------|
| **Overdue** | `due_by < today` — red badge |
| **Due soon** | `today <= due_by <= today + offset` for any offset in type's `reminder_offsets` — amber badge |
| **OK** | otherwise — no badge or subtle styling |

Sort: overdue first, then due-soon, then by `due_by` ascending.

## Audit Trail

Three layers:

1. **Obligation rows** — one per cycle; `series_id` links recurrence history
2. **ObligationEvent** — forward-only status steps (`status_by`, timestamps); notes editable while active
3. **ObligationEventDocument** — file uploads; voided rows retained for audit
4. **ObligationAuditLog** — note edits and obligation field corrections

Query full series history: `WHERE series_id = ?` ordered by `due_by`.

## Recurrence & Series

```text
series_id: abc-123
  ├── Obligation (Jan, Done)
  ├── Obligation (Feb, Done)
  └── Obligation (Mar, Open)   ← current

series_ended_at: null     → Done spawns next
series_ended_at: <date>     → Done does not spawn
```

Explicit `series_id` (not title+type matching) avoids collisions from duplicate titles, renames, or manual duplicates.

## Out of Scope (v1)

- Subjects / subject types (client, asset linking) — use title for context
- In-app notifications / notification bell / Oban reminder jobs
- Email/SMS reminders
- REST API / mobile app
- Billing integration beyond `plan` / `seat_limit` fields on entity
- Field-level audit for obligation type definition changes

## Open Implementation Details

- File storage backend for `documents`
- `due_by` type: date vs utc_datetime (entity timezone handling)
- System preset seed data for Malaysia regulatory types