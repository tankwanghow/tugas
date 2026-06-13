# Argus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Argus — a multi-tenant Phoenix LiveView app for tracking obligations with event-based audit trails, recurrence via `series_id`, and dashboard urgency badges.

**Architecture:** Phoenix 1.8 LiveView monolith with PostgreSQL. Multi-tenancy via `entities` scoped routes (`/entities/:slug/...`). Domain logic in context modules (`Argus.Obligations`, `Argus.Entities`, `Argus.Accounts`). Dashboard computes overdue/due-soon from `due_by` and type `reminder_offsets` — no background jobs. Local filesystem uploads for v1 documents.

**Tech Stack:** Elixir 1.19, OTP 28, Phoenix 1.8, LiveView 1.1, Ecto 3.13, PostgreSQL (citext), Tailwind, bcrypt

**Spec:** `docs/superpowers/specs/2026-06-13-argus-design.md`

---

## File map (created incrementally)

```text
lib/argus/
  schema.ex                          # use Argus.Schema — binary_id PKs
  repo.ex
  application.ex
  accounts.ex                        # users, tokens, registration, login
  accounts/user.ex
  accounts/user_token.ex
  entities.ex                        # entities, memberships, invitations
  entities/entity.ex
  entities/membership.ex
  entities/invitation.ex
  obligations.ex                     # public context API
  obligations/type.ex
  obligations/obligation.ex
  obligations/event.ex
  obligations/event_document.ex
  obligations/audit_log.ex
  obligations/recurrence.ex          # next-due calculation
  obligations/completion.ex          # Done validation
  obligations/series.ex              # series_ended?/end_series
  obligations/urgency.ex             # overdue / due_soon badges from reminder_offsets
  authorization.ex                   # can?(user, action, entity)
  uploads.ex                         # local file storage

lib/argus_web/
  router.ex
  plugs/set_active_entity.ex
  plugs/require_role.ex
  live/entity_live/select.ex
  live/dashboard_live/index.ex
  live/obligation_live/index.ex
  live/obligation_live/show.ex       # workflow: open → in_progress → done
  live/obligation_live/form.ex
  live/obligation_type_live/index.ex
  live/obligation_type_live/form.ex
  live/membership_live/index.ex
  components/layouts/
  components/urgency_badge.ex

priv/repo/migrations/              # one migration per table group
priv/repo/seeds.exs                # system obligation type presets
test/argus/                        # context tests (TDD)
test/argus_web/live/               # LiveView tests
```

---

## Task 1: Bootstrap Phoenix project

**Files:**
- Create: entire project via `mix phx.new`

- [ ] **Step 1: Generate app**

```bash
cd /home/tankwanghow/Projects/elixir
mix phx.new argus --binary-id --no-mailer --no-dashboard --no-assets
```

When prompted for `argus` directory already exists (has `docs/`), answer **Y** to continue.

- [ ] **Step 2: Add dependencies**

Modify `mix.exs` deps list — add:

```elixir
{:bcrypt_elixir, "~> 3.0"},
{:tzdata, "~> 1.1"}
```

Run: `mix deps.get`

- [ ] **Step 3: Verify boot**

Run: `mix test`  
Expected: PASS (0 failures, generated scaffold tests)

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: bootstrap Phoenix app"
```

---

## Task 2: Base schema and citext extension

**Files:**
- Create: `lib/argus/schema.ex`
- Create: `priv/repo/migrations/20260613000001_enable_extensions.exs`

- [ ] **Step 1: Write Schema module**

```elixir
# lib/argus/schema.ex
defmodule Argus.Schema do
  defmacro __using__(_) do
    quote do
      use Ecto.Schema
      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime]
    end
  end
end
```

- [ ] **Step 2: Migration for extensions**

```elixir
# priv/repo/migrations/20260613000001_enable_extensions.exs
defmodule Argus.Repo.Migrations.EnableExtensions do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""
  end
end
```

- [ ] **Step 3: Run migration**

Run: `mix ecto.migrate`  
Expected: `enable_extensions` migrated

- [ ] **Step 4: Commit**

```bash
git add lib/argus/schema.ex priv/repo/migrations/
git commit -m "chore: add Argus.Schema and citext extension"
```

---

## Task 3: Users and auth tokens

**Files:**
- Create: `priv/repo/migrations/20260613000002_create_users.exs`
- Create: `lib/argus/accounts/user.ex`
- Create: `lib/argus/accounts/user_token.ex`
- Create: `lib/argus/accounts.ex`
- Create: `test/argus/accounts_test.exs`
- Create: `test/support/fixtures/accounts_fixtures.ex`

- [ ] **Step 1: Write failing test**

```elixir
# test/argus/accounts_test.exs
defmodule Argus.AccountsTest do
  use Argus.DataCase, async: true
  alias Argus.Accounts
  import Argus.AccountsFixtures

  describe "register_user/1" do
    test "registers with email and password" do
      {:ok, user} = Accounts.register_user(%{email: "a@b.com", password: "password123456"})
      assert user.email == "a@b.com"
      assert user.locale == "en"
      refute user.hashed_password == "password123456"
    end
  end

  describe "authenticate_user/2" do
    test "returns user on valid credentials" do
      user = user_fixture()
      assert {:ok, ^user} = Accounts.authenticate_user(user.email, "password123456")
    end
  end
end
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `mix test test/argus/accounts_test.exs`  
Expected: FAIL — modules not defined

- [ ] **Step 3: Migration**

```elixir
defmodule Argus.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :citext, null: false
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime
      add :locale, :string, null: false, default: "en"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])

    create table(:users_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :authenticated_at, :utc_datetime
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
```

- [ ] **Step 4: Implement User, UserToken, Accounts**

`User` changeset: cast `email`, `locale`; validate email format; `hash_password` with bcrypt.

`Accounts.register_user/1`, `Accounts.authenticate_user/2`, `Accounts.get_user!/1`.

Follow Phoenix 1.8 generated auth patterns (session tokens, `users_tokens`).

- [ ] **Step 5: Run tests**

Run: `mix test test/argus/accounts_test.exs`  
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git commit -am "feat: users and authentication"
```

---

## Task 4: Entities, memberships, invitations

**Files:**
- Create: `priv/repo/migrations/20260613000003_create_entities.exs`
- Create: `lib/argus/entities/entity.ex`
- Create: `lib/argus/entities/membership.ex`
- Create: `lib/argus/entities/invitation.ex`
- Create: `lib/argus/entities.ex`
- Create: `test/argus/entities_test.exs`

- [ ] **Step 1: Write failing test**

```elixir
test "create_entity/2 creates entity and admin membership" do
  user = user_fixture()
  {:ok, entity} = Entities.create_entity(user, %{slug: "acme", name: "Acme Sdn Bhd"})
  assert entity.slug == "acme"
  membership = Entities.get_membership!(user, entity)
  assert membership.role == "admin"
end
```

- [ ] **Step 2: Migration** — per spec (`entities`, `memberships`, `entity_invitations`); use `binary_id` FKs; partial unique index on `memberships_one_default_per_user`.

- [ ] **Step 3: Implement Entities context**

Key functions:
- `create_entity/2` — insert entity + admin membership
- `list_user_entities/1`
- `get_entity_by_slug_for_user!/2` — slug lookup scoped to the user's memberships (used by `SetActiveEntity`)
- `get_membership!/2`
- `invite_member/4` — manager/admin only (authorization added later)
- `accept_invitation/2`

- [ ] **Step 4: Run tests — PASS**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat: entities, memberships, invitations"
```

---

## Task 5: Active entity plug and scoped router

**Files:**
- Create: `lib/argus_web/plugs/set_active_entity.ex`
- Modify: `lib/argus_web/router.ex`
- Create: `test/argus_web/plugs/set_active_entity_test.exs`

- [ ] **Step 1: Plug stores `active_entity_id` in session after membership check**

```elixir
defmodule ArgusWeb.Plugs.SetActiveEntity do
  import Plug.Conn
  alias Argus.Entities

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns.current_user
    slug = conn.params["entity_slug"] || conn.params["slug"]

    entity = Entities.get_entity_by_slug_for_user!(user, slug)
    membership = Entities.get_membership!(user, entity)

    conn
    |> assign(:active_entity, entity)
    |> assign(:membership, membership)
    |> put_session(:active_entity_id, entity.id)
  end
end
```

- [ ] **Step 2: Router scope**

```elixir
scope "/entities/:entity_slug", ArgusWeb do
  pipe_through [:browser, :require_authenticated_user, :set_active_entity]

  live_session :entity, on_mount: [{ArgusWeb.UserAuth, :ensure_authenticated}] do
    live "/", DashboardLive.Index, :index
    live "/obligations", ObligationLive.Index, :index
    live "/obligations/new", ObligationLive.Form, :new
    live "/obligations/:id", ObligationLive.Show, :show
    live "/obligation-types", ObligationTypeLive.Index, :index
    live "/members", MembershipLive.Index, :index
  end
end
```

- [ ] **Step 3: Entity picker LiveView** at `/entities` for users with multiple memberships.

- [ ] **Step 4: Commit**

```bash
git commit -am "feat: entity-scoped routing and active entity plug"
```

---

## Task 6: Authorization module

**Files:**
- Create: `lib/argus/authorization.ex`
- Create: `test/argus/authorization_test.exs`

- [ ] **Step 1: Write failing tests**

```elixir
test "manager can create obligation" do
  {user, entity} = manager_fixture()
  assert Authorization.can?(user, :create_obligation, entity)
end

test "member cannot cancel obligation" do
  {user, entity} = member_fixture()
  refute Authorization.can?(user, :cancel_obligation, entity)
end

test "collaborator cannot mark done" do
  {user, entity, obligation} = collaborator_fixture()
  refute Authorization.can?(user, :mark_done, entity, obligation)
end
```

- [ ] **Step 2: Implement `can?/3` and `can?/4`**

Actions: `:manage_entity`, `:manage_types`, `:create_obligation`, `:edit_obligation`, `:mark_done`, `:cancel_obligation`, `:end_series`, `:void_document`, `:start_progress`

Rules per spec:
- admin → all
- manager → create, edit, mark_done (any), cancel, end_series
- member → start_progress if primary or collaborator; mark_done if primary only

- [ ] **Step 3: Run tests — PASS**

- [ ] **Step 4: Commit**

---

## Task 7: Obligation types schema and recurrence helper

**Files:**
- Create: `priv/repo/migrations/20260613000004_create_obligation_types.exs`
- Create: `lib/argus/obligations/type.ex`
- Create: `lib/argus/obligations/recurrence.ex`
- Create: `test/argus/obligations/recurrence_test.exs`

- [ ] **Step 1: Write failing recurrence tests**

```elixir
defmodule Argus.Obligations.RecurrenceTest do
  use ExUnit.Case, async: true
  alias Argus.Obligations.Recurrence
  alias Argus.Obligations.Type

  test "next_due_suggestion monthly adds one month" do
    type = %Type{recurring_interval: "monthly"}
    assert Recurrence.next_due_suggestion(type, ~D[2026-01-15]) == ~D[2026-02-15]
  end

  test "custom interval returns nil" do
    type = %Type{recurring_interval: "custom"}
    assert Recurrence.next_due_suggestion(type, ~D[2026-01-15]) == nil
  end

  test "none interval returns nil" do
    type = %Type{recurring_interval: "none"}
    assert Recurrence.next_due_suggestion(type, ~D[2026-01-15]) == nil
  end

  test "none is not recurring" do
    type = %Type{recurring_interval: "none"}
    refute Recurrence.recurring?(type)
  end
end
```

- [ ] **Step 2: Implement Recurrence**

```elixir
defmodule Argus.Obligations.Recurrence do
  alias Argus.Obligations.Type

  @intervals ~w(none weekly every_two_weeks monthly quarterly semiannual annual custom)

  def intervals, do: @intervals

  def recurring?(%Type{recurring_interval: "none"}), do: false
  def recurring?(%Type{}), do: true

  def next_due_suggestion(%Type{recurring_interval: "none"}, _due_by), do: nil
  def next_due_suggestion(%Type{recurring_interval: "custom"}, _due_by), do: nil
  def next_due_suggestion(%Type{recurring_interval: interval}, due_by) do
    case interval do
      "weekly" -> Date.add(due_by, 7)
      "every_two_weeks" -> Date.add(due_by, 14)
      "monthly" -> shift_month(due_by, 1)
      "quarterly" -> shift_month(due_by, 3)
      "semiannual" -> shift_month(due_by, 6)
      "annual" -> shift_month(due_by, 12)
      _ -> nil
    end
  end

  defp shift_month(date, n) do
    # use `:calendar` or Timex-free logic; clamp day to end of month
    %{date | month: date.month + n}  # replace with proper month-add helper in impl
  end
end
```

Implement `shift_month/2` properly (handle Jan 31 + 1 month → Feb 28).

- [ ] **Step 3: Migration for obligation_types**

Fields per spec. `entity_id` nullable for system presets.

- [ ] **Step 4: Type changeset validates interval in `@intervals` and the CSV-in-string fields**

`reminder_offsets` and `complete_documents` are stored as comma-delimited strings but are parsed
on the **dashboard render path** — a malformed value would raise and take down the whole
entity's dashboard. Validate and normalize them at **write time** so render-time parsing can
never fail:

- `reminder_offsets` — each comma-separated token must parse to a **non-negative integer**;
  reject otherwise with a changeset error. Normalize: trim, drop blanks, dedup, sort; store
  canonical `"30,7,1"`. Add a test for a bad value (`"7, ,abc"`) producing an invalid changeset.
- `complete_documents` — trim each slot name, drop blanks, dedup; reject duplicate or empty slot
  names. Store canonical form.

Add a failing changeset test for each before implementing.

- [ ] **Step 5: Run tests — PASS**

- [ ] **Step 6: Commit**

---

## Task 8: Obligations, events, collaborators

**Files:**
- Create: `priv/repo/migrations/20260613000005_create_obligations.exs`
- Create: `lib/argus/obligations/obligation.ex`
- Create: `lib/argus/obligations/event.ex`
- Create: `lib/argus/obligations.ex` (partial — create only)
- Create: `test/argus/obligations_test.exs`
- Create: `test/support/fixtures/obligations_fixtures.ex`

> **Fixture caveat (carries through Tasks 9–12, 14):** `obligation_fixture/*` and
> `recurring_obligation_fixture/*` must build their `ObligationType` with
> `complete_note_required: false` and `complete_documents: ""` (no required slots) **by default**.
> Otherwise the Task 9 `complete/4` tests for `next_due_required`, idempotency (`not_live`), and
> plain spawn would fail on the note/document validations *before* reaching the behavior under
> test. Tests that specifically exercise completion rules should opt **in** to those requirements
> via fixture options (e.g. `type_fixture(entity, complete_note_required: true)`), not rely on the
> default.

- [ ] **Step 1: Write failing create test**

```elixir
test "create_obligation/3 creates obligation, open event, and optional open note" do
  {manager, entity} = manager_fixture()
  type = type_fixture(entity)
  assignee = member_fixture(entity)

  attrs = %{
    title: "EPF Jan",
    obligation_type_id: type.id,
    primary_assignee_id: assignee.id,
    due_by: ~D[2026-01-15],
    open_note: "Submit by 15th"
  }

  {:ok, obligation} = Obligations.create_obligation(entity, manager, attrs)
  assert obligation.series_id
  assert obligation.status == "active"

  events = Obligations.list_events(obligation)
  assert hd(events).status == "open"

  assert hd(events).note == "Submit by 15th"
end
```

- [ ] **Step 2: Migration**

Tables: `obligations`, `obligation_collaborators`, `obligation_events`.

`obligations` columns include `completed_at :utc_datetime` (nullable) and `series_ended_at :utc_datetime` (nullable).

Use `due_by` as `:date`. Index `(entity_id, status)`, `(series_id)`, `(primary_assignee_id)`.

**Enforce one live cycle per series** with a partial unique index (a live cycle is
`status = 'active' AND completed_at IS NULL`):

```elixir
create unique_index(:obligations, [:series_id],
  where: "status = 'active' AND completed_at IS NULL",
  name: :obligations_one_live_cycle_per_series)
```

This is what makes concurrent Done calls safe — the second spawn of the same series hits the index and fails.

- [ ] **Step 3: Implement `create_obligation/3` in transaction**

1. Generate `series_id` with `Ecto.UUID.generate()`
2. Insert obligation
3. Insert collaborators if provided
4. Insert open event with optional `note` (from `open_note` attr)

- [ ] **Step 4: Run tests — PASS**

- [ ] **Step 5: Commit**

---

## Task 9: Workflow transitions (in_progress, done, spawn next)

**Files:**
- Create: `lib/argus/obligations/completion.ex`
- Modify: `lib/argus/obligations.ex`
- Modify: `test/argus/obligations_test.exs`

- [ ] **Step 1: Write failing tests**

```elixir
test "start_progress/3 creates in_progress event" do
  {member, entity, obligation} = assigned_member_fixture()
  {:ok, event} = Obligations.start_progress(entity, member, obligation)
  assert event.status == "in_progress"
end

test "complete/4 marks done, stamps completed_at, and spawns next when recurring" do
  {primary, entity, obligation} = recurring_obligation_fixture(interval: "monthly")
  {:ok, done_obligation, new_obligation} =
    Obligations.complete(entity, primary, obligation, %{next_due_by: ~D[2026-02-15]})

  assert done_obligation.completed_at                     # terminal marker set
  assert done_event = Obligations.latest_event(done_obligation)
  assert done_event.status == "done"
  assert new_obligation.due_by == ~D[2026-02-15]
  assert new_obligation.series_id == obligation.series_id
end

test "complete/4 requires next_due_by for a recurring, not-ended series" do
  {primary, entity, obligation} = recurring_obligation_fixture(interval: "monthly")
  # Omitting next_due_by would leave the series with no successor cycle → rejected
  assert {:error, :next_due_required} = Obligations.complete(entity, primary, obligation, %{})
end

test "complete/4 is idempotent — a second Done on the same cycle is rejected" do
  {primary, entity, obligation} = recurring_obligation_fixture(interval: "monthly")
  {:ok, done_obligation, _} =
    Obligations.complete(entity, primary, obligation, %{next_due_by: ~D[2026-02-15]})
  # The cycle is no longer live (completed_at set) — re-completing fails
  assert {:error, :not_live} = Obligations.complete(entity, primary, done_obligation, %{next_due_by: ~D[2026-03-15]})
end

test "end_series cancels the current cycle, so it can never be completed/spawn" do
  {manager, entity, obligation} = recurring_obligation_fixture(interval: "monthly")
  {:ok, ended} = Obligations.end_series(entity, manager, obligation, %{})
  # End series == cancel current obligation + stamp series_ended_at (semantics A)
  assert ended.status == "cancelled"
  assert ended.series_ended_at
  # A non-live (cancelled) cycle cannot be completed — no next obligation is ever spawned
  assert {:error, :not_live} = Obligations.complete(entity, manager, ended, %{})
end
```

- [ ] **Step 2: Implement Completion validation**

```elixir
defmodule Argus.Obligations.Completion do
  def validate_done_requirements(type, done_attrs, documents) do
    with :ok <- validate_note(type, done_attrs[:note]),
         :ok <- validate_document_slots(type, documents) do
      :ok
    end
  end

  defp validate_note(%{complete_note_required: true}, note) when note in [nil, ""],
    do: {:error, :note_required}

  defp validate_note(_, _), do: :ok

  defp validate_document_slots(type, documents) do
    required = type.complete_documents |> parse_csv()
    slots = documents |> Enum.reject(& &1.voided_at) |> Map.new(&{&1.document_slot, true})

    case Enum.find(required, &(not Map.has_key?(slots, &1))) do
      nil -> :ok
      missing -> {:error, {:missing_document, missing}}
    end
  end
end
```

- [ ] **Step 3: Implement `complete/4`**

In `Ecto.Multi`:
1. Validate authorization (`mark_done`)
2. Validate completion requirements
3. **Recurrence guard:** if `Recurrence.recurring?(type)` and not `Series.ended?(series_id)` → `next_due_by` is **required**; missing/blank → `{:error, :next_due_required}`. (This guarantees no series ever loses its successor cycle — fix 5.)
4. **Guarded close (concurrency + idempotency):** stamp `completed_at` with a conditional update —
   `from(o in Obligation, where: o.id == ^id and is_nil(o.completed_at) and o.status == "active")
   |> Repo.update_all(set: [completed_at: now])`. If `0` rows are updated, abort the Multi with
   `{:error, :not_live}` (someone already completed/cancelled it). This is the single source of
   truth for "is this cycle still live", replacing any in-memory `status` check.
5. Insert `done` event + document
6. If recurring and not ended → `create_obligation` with same `series_id`, copy assignees/collaborators (the partial unique index on `series_id` is the backstop against a duplicate spawn)

Return `{:ok, completed, new_obligation | nil}`

- [ ] **Step 4: Implement `Series.ended?/1`** — `Repo.exists?` where `series_id` and `series_ended_at` not nil. Under semantics A, End series cancels the current cycle, so a *live* obligation in an ended series can't exist — this guard is defensive only.

- [ ] **Step 5: Run tests — PASS**

- [ ] **Step 6: Commit**

---

## Task 10: Cancel and end series

**Files:**
- Modify: `lib/argus/obligations.ex`
- Modify: `test/argus/obligations_test.exs`

- [ ] **Step 1: Tests**

```elixir
test "cancel_obligation/3 sets status cancelled and logs event" do
  {manager, entity, obligation} = obligation_fixture()
  {:ok, cancelled} = Obligations.cancel_obligation(entity, manager, obligation, %{})
  assert cancelled.status == "cancelled"
end

test "end_series cancels current obligation and sets series_ended_at" do
  {manager, entity, obligation} = recurring_obligation_fixture()
  {:ok, ended} = Obligations.end_series(entity, manager, obligation, %{})
  assert ended.status == "cancelled"
  assert ended.series_ended_at
end
```

- [ ] **Step 2: Implement** — manager/admin only; insert `cancelled` event and set `status: "cancelled"`. `end_series` does the same **plus** sets `series_ended_at` on the current obligation (semantics A: ending a series cancels the in-flight cycle).

- [ ] **Step 3: Run tests — PASS**

- [ ] **Step 4: Commit**

---

## Task 11: Event documents and uploads

**Files:**
- Create: `priv/repo/migrations/20260613000006_create_obligation_event_documents.exs`
- Create: `lib/argus/obligations/event_document.ex`
- Create: `lib/argus/uploads.ex`
- Modify: `lib/argus/obligations.ex`

- [ ] **Step 1: Migration** for `obligation_event_documents` per spec (void fields included).

- [ ] **Step 2: Uploads module** — store under `priv/uploads/:entity_id/:obligation_id/`; save original filename in DB JSON/map field `documents`.

```elixir
def store(%Plug.Upload{} = upload, entity_id, obligation_id) do
  dest_dir = Path.join([:code.priv_dir(:argus), "uploads", entity_id, obligation_id])
  File.mkdir_p!(dest_dir)
  filename = "#{Ecto.UUID.generate()}_#{upload.filename}"
  dest = Path.join(dest_dir, filename)
  File.cp!(upload.path, dest)
  %{filename: filename, original: upload.filename, path: dest}
end
```

- [ ] **Step 3: `add_document/5` and `void_document/4`** with authorization rules.

- [ ] **Step 4: Tests for void excluding from completion validation**

- [ ] **Step 5: Commit**

---

## Task 12: Audit log and corrections

**Files:**
- Create: `priv/repo/migrations/20260613000007_create_obligation_audit_logs.exs`
- Create: `lib/argus/obligations/audit_log.ex`
- Modify: `lib/argus/obligations.ex`
- Create: `test/argus/obligations/audit_test.exs`

- [ ] **Step 1: Tests**

```elixir
test "update_obligation/4 logs title change" do
  {manager, entity, obligation} = obligation_fixture()
  {:ok, updated} = Obligations.update_obligation(entity, manager, obligation, %{title: "New"})
  logs = Obligations.list_audit_logs(obligation)
  assert Enum.any?(logs, &(&1.field == "title"))
end

test "member cannot update title" do
  {member, entity, obligation} = assigned_member_fixture()
  assert {:error, :unauthorized} = Obligations.update_obligation(entity, member, obligation, %{title: "X"})
end
```

- [ ] **Step 2: Implement `update_obligation/4`** — only active obligations; manager/admin; log each changed field.

- [ ] **Step 3: `edit_note/4`** — 48-hour window for author; manager/admin override; log change.

- [ ] **Step 4: Commit**

---

## Task 13: System obligation type seeds

**Files:**
- Modify: `priv/repo/seeds.exs`

- [ ] **Step 1: Seed Malaysia presets** (`entity_id: nil`)

Examples:
- EPF Monthly — `monthly`, `complete_documents: "payment_receipt"`
- SOCSO Monthly — `monthly`
- SST Return — `quarterly`
- SSM Annual Return — `annual`
- LHDN Tax Estimation — `custom`

- [ ] **Step 2: `mix run priv/repo/seeds.exs` — no errors**

- [ ] **Step 3: Commit**

---

## Task 14: Urgency badges (replaces notifications)

**Files:**
- Create: `lib/argus/obligations/urgency.ex`
- Create: `lib/argus_web/components/urgency_badge.ex`
- Create: `test/argus/obligations/urgency_test.exs`

- [ ] **Step 1: Write failing tests**

```elixir
defmodule Argus.Obligations.UrgencyTest do
  use ExUnit.Case, async: true
  alias Argus.Obligations.Urgency
  alias Argus.Obligations.Type

  @today ~D[2026-06-13]

  test "overdue when due_by is in the past" do
    type = %Type{reminder_offsets: "7,1"}
    assert Urgency.classify(type, ~D[2026-06-10], @today) == :overdue
  end

  test "due_soon when within reminder offset" do
    type = %Type{reminder_offsets: "7,1"}
    assert Urgency.classify(type, ~D[2026-06-18], @today) == :due_soon
  end

  test "ok when outside reminder offsets" do
    type = %Type{reminder_offsets: "7,1"}
    assert Urgency.classify(type, ~D[2026-07-01], @today) == :ok
  end
end
```

- [ ] **Step 2: Implement Urgency**

```elixir
defmodule Argus.Obligations.Urgency do
  alias Argus.Obligations.Type

  @type urgency :: :overdue | :due_soon | :ok

  # `today` is REQUIRED — callers pass the date in the entity's timezone (see today_for/1).
  # No UTC default: defaulting to Date.utc_today() silently mis-dates non-UTC tenants.
  @spec classify(Type.t(), Date.t(), Date.t()) :: urgency()
  def classify(%Type{reminder_offsets: offsets}, due_by, today) do
    cond do
      Date.compare(due_by, today) == :lt -> :overdue
      due_soon?(offsets, due_by, today) -> :due_soon
      true -> :ok
    end
  end

  # "Today" in the entity's timezone — fix 3. Dashboards compute this once and pass it in.
  @spec today_for(String.t()) :: Date.t()
  def today_for(timezone) do
    case DateTime.now(timezone) do
      {:ok, dt} -> DateTime.to_date(dt)
      _ -> Date.utc_today()            # fall back only if the tz is unknown to tzdata
    end
  end

  defp due_soon?(offsets, due_by, today) do
    days = Date.diff(due_by, today)

    offsets
    |> parse_offsets()
    |> Enum.any?(fn offset -> days <= offset end)
  end

  # Defensive even though Type validates at write time (fix 4): skip non-integer/blank tokens
  # rather than raising on the render path. Empty/nil → a sane default offset.
  def parse_offsets(nil), do: [7]
  def parse_offsets(str) do
    parsed =
      str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.flat_map(fn tok ->
        case Integer.parse(tok) do
          {n, ""} when n >= 0 -> [n]
          _ -> []
        end
      end)

    if parsed == [], do: [7], else: parsed
  end
end
```

- [ ] **Step 3: UrgencyBadge component** — red for `:overdue`, amber for `:due_soon`, hidden for `:ok`

- [ ] **Step 4: Run tests — PASS**

- [ ] **Step 5: Commit**

---

## Task 15: Dashboard LiveView (split view)

**Files:**
- Create: `lib/argus_web/live/dashboard_live/index.ex`
- Create: `test/argus_web/live/dashboard_live_test.exs`

- [ ] **Step 1: Test renders My work and Team overview tabs**

Member default tab: `my_work`. Manager default: `team`.

- [ ] **Step 2: Queries**

Filter is **live cycles only** — `status == "active" AND is_nil(completed_at)`. Filtering on
`status` alone would leak completed obligations onto the dashboard forever (they keep
`status = "active"`).

```elixir
def list_my_work(entity, user) do
  from o in Obligation,
    where: o.entity_id == ^entity.id and o.status == "active" and is_nil(o.completed_at),
    where: o.primary_assignee_id == ^user.id or o.id in subquery(collaborator_ids(user)),
    order_by: [asc: o.due_by]
end

def list_team_overview(entity) do
  from o in Obligation,
    where: o.entity_id == ^entity.id and o.status == "active" and is_nil(o.completed_at),
    order_by: [asc: o.due_by]
end
```

- [ ] **Step 3: UI** — table with title, type, assignee, due_by, `<.urgency_badge>`. Compute
  `today = Urgency.today_for(entity.timezone)` **once** in `mount` and pass it to every
  `classify/3` call (fix 3). Sort overdue first, then due_soon, then `due_by` asc.

- [ ] **Step 4: Commit**

---

## Task 16: Obligation LiveViews (form, show, workflow)

**Files:**
- Create: `lib/argus_web/live/obligation_live/form.ex`
- Create: `lib/argus_web/live/obligation_live/show.ex`
- Create: `lib/argus_web/live/obligation_live/index.ex`
- Create: `test/argus_web/live/obligation_live_test.exs`

- [ ] **Step 1: Form** — manager-only; fields: title, type, primary assignee, collaborators (multi-select), due_by, open_note.

- [ ] **Step 2: Show page sections**

1. Header — title, type, due_by, assignees
2. Event timeline — open → in_progress → done/cancelled
3. Documents per event
4. Actions (role-gated): Start progress, Add note/doc, Done (modal with next due date picker), Cancel, End series

- [ ] **Step 3: Done modal**

- If recurring **and series not ended**: show a date input that is **required** — the modal
  cannot be submitted without a next due date (mirrors the `{:error, :next_due_required}` guard
  in `complete/4`, fix 5). To finish a recurring obligation *without* a successor, the user picks
  **End series** instead, not blank-submit.
- Pre-fill via `Recurrence.next_due_suggestion/2` for fixed intervals; blank for `custom` (user must pick)
- Enforce note/doc fields per type on submit

- [ ] **Step 4: LiveView tests** for create, start_progress, complete with spawn, and that the
  Done modal blocks submit when a recurring obligation has no next due date

- [ ] **Step 5: Commit**

---

## Task 17: Obligation types management UI

**Files:**
- Create: `lib/argus_web/live/obligation_type_live/index.ex`
- Create: `lib/argus_web/live/obligation_type_live/form.ex`

- [ ] **Step 1: Index** — list system presets (read-only) + entity custom types

- [ ] **Step 2: Form** — manager/admin clone or create; fields per Type schema including interval select with all 8 values.

- [ ] **Step 3: Commit**

---

## Task 18: Membership management UI

**Files:**
- Create: `lib/argus_web/live/membership_live/index.ex`

- [ ] **Step 1: List members, invite form (email + role), pending invitations**

- [ ] **Step 2: Admin can change roles; seat_limit check on invite**

- [ ] **Step 3: Commit**

---

## Task 19: Series history on obligation show

**Files:**
- Modify: `lib/argus_web/live/obligation_live/show.ex`

- [ ] **Step 1: Sidebar or tab "Series history"** — `Obligations.list_series(series_id)` ordered by `due_by`

- [ ] **Step 2: Link to completed obligations (read-only view)**

- [ ] **Step 3: Commit**

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Users without timezone | Task 3 |
| Entities, memberships, invitations | Task 4 |
| Roles admin/manager/member | Task 6 |
| Primary + collaborators | Task 8 |
| Done: primary or manager | Task 6, 9 |
| Obligation types + intervals | Task 7, 13, 17 |
| custom interval manual date | Task 7, 16 |
| Event workflow open/in_progress/done | Task 8, 9, 16 |
| Recurrence spawns new obligation | Task 9 |
| series_id linking | Task 8, 9, 19 |
| Cancel + end series | Task 10 |
| Completion rules on Done | Task 9 |
| Terminal `completed_at` (dashboards exclude done cycles) | Task 8, 9, 15 |
| One live cycle per series (partial unique index) | Task 8, 9 |
| Idempotent / concurrency-safe Done | Task 9 |
| Recurring Done requires next_due_by (no series limbo) | Task 9, 16 |
| Urgency uses entity timezone | Task 14, 15 |
| CSV type fields validated at write time | Task 7 |
| Incremental documents + void | Task 11 |
| Audit log corrections | Task 12 |
| Dashboard urgency badges | Task 14, 15 |
| Dashboard split view | Task 15 |
| Lock after Done | Task 12 |

## Deferred (spec open items)

- In-app notifications / Oban reminder jobs → out of scope v1
- Email/SMS notifications → out of scope
- Subjects → out of scope

---

## Final verification

- [ ] Run full suite: `mix test`
- [ ] Run credo: `mix credo` (add if desired)
- [ ] Manual smoke: register → create entity → create type → create obligation → progress → done → verify spawn → verify dashboard urgency badges

```bash
mix phx.server
```