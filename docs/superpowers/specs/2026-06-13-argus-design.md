# Argus — Multi-Tenant Obligations Tracking System

**Date:** 2026-06-13  
**Status:** Approved for implementation planning

## Overview

Argus is a multi-tenant web application for tracking obligations — regulatory filings, operational renewals, client deliverables, and custom deadlines. Users define obligation types (with system presets), assign work to team members, track progress with notes and documents, and receive in-app reminders before due dates.

**Tech stack:** Phoenix LiveView monolith, PostgreSQL, Oban (reminders).

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
| `reminder_offsets` | string | Comma-delimited days before due, e.g. `"30,7,1"` |

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
| `series_ended_at` | utc_datetime nullable | Set by "End series" — blocks future spawn |

### obligation_collaborators

| Field | Type |
|-------|------|
| `obligation_id` | FK |
| `user_id` | FK |

Unique `(obligation_id, user_id)`.

### ObligationEvent

One row per workflow step — append-only audit trail. Grouped by `obligation_id` (one obligation row per cycle; no `due_by` duplicate needed on events).

| Field | Type | Notes |
|-------|------|-------|
| `obligation_id` | FK | |
| `status` | enum | `open`, `in_progress`, `done`, `cancelled` |
| `status_by_id` | FK → users | Who triggered this step |
| `note` | text nullable | Step note — open context, done comment, cancel reason; enforced on Done when `complete_note_required` |
| `inserted_at` | utc_datetime | |

Event rows are never edited or deleted. Note edits while active → `ObligationAuditLog`.

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

### InAppNotification (v1 reminders)

| Field | Type | Notes |
|-------|------|-------|
| `user_id` | FK | |
| `obligation_id` | FK | |
| `kind` | string | e.g. `reminder` |
| `read_at` | utc_datetime nullable | |
| `inserted_at` | utc_datetime | |

## Workflows

### Create Obligation

1. Manager fills: title, type, primary assignee, optional collaborators, due_by
2. Optional "Notes" on form → saved as `note` on Open event (serves as description/context)
3. System creates `Obligation` (`status: active`, new `series_id`)
4. System creates `ObligationEvent` (`status: open`, `due_by` snapshot)

### Work (optional)

While cycle is active (not yet `done`):

- Transition to `in_progress` (one event per cycle)
- Add documents incrementally on the `open` or `in_progress` event (multiple `ObligationEventDocument` rows over time)
- Step-level notes live on `ObligationEvent.note` (open context, done comment, cancel reason)

Note and document requirements on type are **not** enforced until Done — only on Done.

### Done

1. User (primary or manager) triggers Done
2. Enforce `ObligationType` rules:
   - `complete_note_required` → `note` present on Done event
   - `complete_documents` → one non-voided file per named slot
3. Create `ObligationEvent` (`status: done`, `note`) + any Done document uploads
4. If `recurring_interval` is not `none` **and** `series_ended_at IS NULL`:
   - Prompt: "Next due date?"
   - Pre-fill from interval formula for fixed intervals (`weekly` … `annual`); blank picker for `custom`
   - Create **new** `Obligation` (same `series_id`, type, title, assignees, collaborators, new `due_by`)
   - Create `ObligationEvent` (`status: open`) on new obligation
5. Completed obligation remains unchanged (historical record)

### Cancel

**Cancel obligation** (manager/admin):

- `Obligation.status → cancelled`
- `ObligationEvent` (`status: cancelled`, optional note)
- No Done rules, no next obligation spawned

**End series** (manager/admin):

- Same as cancel obligation
- Set `series_ended_at` on the obligation (or series record keyed by `series_id`)
- Future Done on any obligation in series does not spawn next cycle

### Reminders (v1: in-app only)

- Oban job checks active obligations' `due_by` against type `reminder_offsets`
- Creates `InAppNotification` for primary assignee (and collaborators TBD)
- Dashboard notification bell; no email in v1

## Corrections Model

Lock after Done/cancelled. Edits while cycle is active.

### Obligation fields (`title`, `due_by`, assignees)

| State | Who can edit |
|-------|----------------|
| Active | manager, admin |
| Done / cancelled | locked |

→ Logged in `ObligationAuditLog`.

### Notes

| Rule | Detail |
|------|--------|
| Author | Edit own note within 15 minutes |
| Override | manager/admin anytime before Done |
| After Done | locked |

→ Logged in `ObligationAuditLog`.

### Documents

- **Void + re-upload** — never hard-delete
- Uploader can void own doc before Done; manager/admin can void any doc before Done
- Admin can void after Done with required reason
- Replacement = new `ObligationEventDocument` row

### Events

Append-only. Wrong status → corrective note on `in_progress` event or cancel obligation.

## Dashboard (v1)

Split view with role-aware default tab:

| Tab | Content | Default for |
|-----|---------|-------------|
| **My work** | Obligations where user is primary or collaborator; active only; sorted by due date | member |
| **Team overview** | All active upcoming/overdue obligations in entity | manager, admin |

Filter: `Obligation.status = active`.

## Audit Trail

Three layers:

1. **Obligation rows** — one per cycle; `series_id` links recurrence history
2. **ObligationEvent** — append-only workflow steps with `status_by` and timestamps
3. **ObligationEventDocument** — incremental notes/files (including voided)
4. **ObligationAuditLog** — field-level corrections

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
- Email/SMS reminders
- REST API / mobile app
- Billing integration beyond `plan` / `seat_limit` fields on entity
- Field-level audit for obligation type definition changes

## Open Implementation Details

- File storage backend for `documents`
- Whether collaborators receive in-app reminders
- `due_by` type: date vs utc_datetime (entity timezone handling)
- System preset seed data for Malaysia regulatory types