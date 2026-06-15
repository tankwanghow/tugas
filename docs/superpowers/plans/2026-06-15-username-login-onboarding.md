# Username + Password Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let admins invite managers/members by single-use email **or** a reusable, admin-supervised QR session; the invitee sets a username + password on first access and logs back in with username-or-email + password.

**Architecture:** Add a globally-unique `username` identifier to `users` (email relaxed to nullable, "at least one identifier" check constraint). Invitations no longer carry identity — their email is delivery-only and optional. Invitations come in two shapes: single-use email (consumed via `accepted_at`) and reusable QR sessions (`reusable=true`, ended by `closed_at` or a 30-min `expires_at`). The accept page (`GET /invitations/:token`) renders only; a `POST .../accept` controller handles three paths (one-click, create-account, log-in-to-accept). An admin invite-session LiveView shows a QR (`eqrcode`) and streams joiners live via PubSub. Password login resolves the typed handle against email then username.

**Tech Stack:** Elixir/Phoenix 1.8, LiveView 1.2, Ecto 3.13, PostgreSQL citext, Bcrypt, daisyUI.

**Spec:** `docs/superpowers/specs/2026-06-15-username-login-onboarding-design.md`

---

## File Structure

- **Migration** `priv/repo/migrations/<ts>_add_username_relax_identity.exs` — schema changes.
- **`lib/argus/accounts/user.ex`** — add `username` field + `registration_changeset/3` and helpers.
- **`lib/argus/accounts.ex`** — `register_invited_user/1`, `get_user_by_username/1`, `get_user_by_login_and_password/2`; remove `get_or_register_invited_user/1`.
- **`lib/argus/entities/invitation.ex`** — relax `changeset/2` (email optional).
- **`lib/argus/entities.ex`** — `invite_member/4` allows nil/blank email.
- **`lib/argus_web/controllers/invitation_controller.ex`** — rewrite `accept/2` (three paths).
- **`lib/argus_web/live/invitation_live/show.ex`** — render branches + forms (plain action POST, no phx-submit).
- **`lib/argus_web/live/user_live/login.ex`** + **`lib/argus_web/controllers/user_session_controller.ex`** — password login accepts username-or-email.
- **`test/support/fixtures/accounts_fixtures.ex`** — `unique_username/0`, `username_user_fixture/1`.
- **`lib/argus/entities/invitation.ex` / `entities.ex`** — `reusable`/`closed_at` + `open_invite_session/2`, `close_invite_session/2`; non-consuming reusable accept + `{:member_joined, _}` PubSub.
- **`lib/argus_web/qr.ex`** — inline SVG QR helper (`eqrcode` dep).
- **`lib/argus_web/live/membership_live/invite_session.ex`** — admin QR session view (QR + live roster + Close).
- Test files mirror each module.

> **Note for the worker:** this branch already carries uncommitted invitation work (the email-auto-register version). Several tasks **rewrite** those existing files rather than create them.

---

## Task 1: Migration — username + relaxed identity

**Files:**
- Create: `priv/repo/migrations/<ts>_add_username_relax_identity.exs` (generate the timestamp)
- Test: `test/argus/accounts_test.exs` (add cases)

- [ ] **Step 1: Generate the migration file**

Run: `mix ecto.gen.migration add_username_relax_identity`
Then replace its body with:

```elixir
defmodule Argus.Repo.Migrations.AddUsernameRelaxIdentity do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :username, :citext
      modify :email, :citext, null: true, from: {:citext, null: false}
    end

    create unique_index(:users, [:username])

    create constraint(:users, :users_email_or_username_required,
             check: "email IS NOT NULL OR username IS NOT NULL"
           )

    alter table(:entity_invitations) do
      modify :email, :citext, null: true, from: {:citext, null: false}
      add :reusable, :boolean, null: false, default: false
      add :closed_at, :utc_datetime
    end

    drop unique_index(:entity_invitations, [:entity_id, :email],
           name: :entity_invitations_one_pending_per_email
         )

    create unique_index(:entity_invitations, [:entity_id, :email],
             where: "accepted_at IS NULL AND email IS NOT NULL",
             name: :entity_invitations_one_pending_per_email
           )
  end
end
```

- [ ] **Step 2: Add the `username` field to the schema (so migrate + tests compile)**

In `lib/argus/accounts/user.ex`, inside `schema "users" do`, add after the `:email` line:

```elixir
    field :username, :string
```

- [ ] **Step 3: Run the migration**

Run: `mix ecto.migrate`
Expected: migrates cleanly; `username` column + unique index + check constraint created.

- [ ] **Step 4: Write the failing test for the check constraint**

Add to `test/argus/accounts_test.exs` (inside the module, new describe block):

```elixir
  describe "identity constraints" do
    test "rejects a user with neither email nor username" do
      assert_raise Ecto.ConstraintError, ~r/users_email_or_username_required/, fn ->
        %Argus.Accounts.User{}
        |> Ecto.Changeset.change(%{locale: "en"})
        |> Argus.Repo.insert!()
      end
    end
  end
```

- [ ] **Step 5: Run it**

Run: `mix test test/argus/accounts_test.exs -o "identity constraints"` (or run the file)
Expected: PASS (constraint already exists from the migration).

- [ ] **Step 6: Commit**

```bash
git add priv/repo/migrations lib/argus/accounts/user.ex test/argus/accounts_test.exs priv/repo/structure.sql
git commit -m "feat: add username identifier and relax email to nullable

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: User.registration_changeset (username + password, optional email)

**Files:**
- Modify: `lib/argus/accounts/user.ex`
- Test: `test/argus/accounts_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/argus/accounts_test.exs`:

```elixir
  describe "registration_changeset/3" do
    alias Argus.Accounts.User

    test "is valid with username + password and no email" do
      cs = User.registration_changeset(%User{}, %{username: "newbie", password: "supersecret12"})
      assert cs.valid?
      assert get_change(cs, :hashed_password)
      refute get_change(cs, :password)
    end

    test "requires a username" do
      cs = User.registration_changeset(%User{}, %{password: "supersecret12"})
      refute cs.valid?
      assert %{username: ["can't be blank"]} = errors_on(cs)
    end

    test "rejects a short password" do
      cs = User.registration_changeset(%User{}, %{username: "newbie", password: "short"})
      refute cs.valid?
      assert %{password: ["should be at least 12 character(s)"]} = errors_on(cs)
    end

    test "validates email format only when an email is given" do
      cs = User.registration_changeset(%User{}, %{username: "n2", password: "supersecret12", email: "bad"})
      refute cs.valid?
      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(cs)
    end
  end
```

Add `import Ecto.Changeset` at the top of `accounts_test.exs` if not already present (for `get_change`).

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/argus/accounts_test.exs`
Expected: FAIL with "function User.registration_changeset/3 is undefined".

- [ ] **Step 3: Implement the changeset and helpers**

In `lib/argus/accounts/user.ex`, add after `email_changeset/3`:

```elixir
  @doc """
  Registers an invited member from a username + password, with an optional
  email. Username is required (it's their login handle); email is optional.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:username, :email, :password, :locale])
    |> validate_username(opts)
    |> maybe_validate_email(opts)
    |> validate_password(opts)
    |> put_default_locale()
  end

  defp validate_username(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:username])
      |> validate_format(:username, ~r/^[a-zA-Z0-9_]+$/,
        message: "only letters, numbers, and underscores"
      )
      |> validate_length(:username, min: 3, max: 30)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:username, Argus.Repo)
      |> unique_constraint(:username)
    else
      changeset
    end
  end

  defp maybe_validate_email(changeset, opts) do
    if get_field(changeset, :email) do
      changeset =
        changeset
        |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
          message: "must have the @ sign and no spaces"
        )
        |> validate_length(:email, max: 160)

      if Keyword.get(opts, :validate_unique, true) do
        changeset |> unsafe_validate_unique(:email, Argus.Repo) |> unique_constraint(:email)
      else
        changeset
      end
    else
      changeset
    end
  end
```

- [ ] **Step 4: Run it to verify it passes**

Run: `mix test test/argus/accounts_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/argus/accounts/user.ex test/argus/accounts_test.exs
git commit -m "feat: User.registration_changeset for username+password members

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Accounts — register_invited_user + login resolvers

**Files:**
- Modify: `lib/argus/accounts.ex` (add 3 functions, remove `get_or_register_invited_user/1`)
- Modify: `test/support/fixtures/accounts_fixtures.ex`
- Test: `test/argus/accounts_test.exs`

- [ ] **Step 1: Add fixture helpers**

In `test/support/fixtures/accounts_fixtures.ex`, add:

```elixir
  def unique_username, do: "user#{System.unique_integer([:positive])}"

  def username_user_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        username: unique_username(),
        password: valid_user_password()
      })

    {:ok, user} = Argus.Accounts.register_invited_user(attrs)
    user
  end
```

- [ ] **Step 2: Write the failing test**

Add to `test/argus/accounts_test.exs`:

```elixir
  describe "register_invited_user/1" do
    test "creates a confirmed user with a hashed password and no email" do
      {:ok, user} = Accounts.register_invited_user(%{username: "joiner1", password: "supersecret12"})
      assert user.username == "joiner1"
      assert user.confirmed_at
      assert user.hashed_password
      assert is_nil(user.email)
    end

    test "rejects a duplicate username (case-insensitive)" do
      {:ok, _} = Accounts.register_invited_user(%{username: "dup", password: "supersecret12"})
      {:error, cs} = Accounts.register_invited_user(%{username: "DUP", password: "supersecret12"})
      assert %{username: ["has already been taken"]} = errors_on(cs)
    end
  end

  describe "get_user_by_login_and_password/2" do
    test "finds by username and verifies the password" do
      user = username_user_fixture(%{username: "loginme"})
      assert %Accounts.User{id: id} = Accounts.get_user_by_login_and_password("loginme", valid_user_password())
      assert id == user.id
    end

    test "finds by email when the user has one" do
      user = user_fixture() |> set_password()
      assert %Accounts.User{id: id} =
               Accounts.get_user_by_login_and_password(user.email, valid_user_password())
      assert id == user.id
    end

    test "returns nil on wrong password" do
      username_user_fixture(%{username: "wrongpw"})
      refute Accounts.get_user_by_login_and_password("wrongpw", "not the password")
    end

    test "returns nil on unknown handle" do
      refute Accounts.get_user_by_login_and_password("nobody", valid_user_password())
    end
  end
```

Add `import Argus.AccountsFixtures` to `accounts_test.exs` if absent. Reference `Accounts.User` is the alias `alias Argus.Accounts.User` — add it to the test module if absent, or use the full name.

- [ ] **Step 3: Run it to verify it fails**

Run: `mix test test/argus/accounts_test.exs`
Expected: FAIL with undefined `register_invited_user/1` and `get_user_by_login_and_password/2`.

- [ ] **Step 4: Implement in `lib/argus/accounts.ex`**

Replace the existing `get_or_register_invited_user/1` doc+function (around line 88-96) with:

```elixir
  @doc """
  Gets a user by username.
  """
  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: username)
  end

  @doc """
  Gets a user by a login handle (email or username) and password.

  Resolves the handle against `email` first, then `username` (both citext, so
  matching is case-insensitive), then verifies the password.
  """
  def get_user_by_login_and_password(login, password)
      when is_binary(login) and is_binary(password) do
    user = Repo.get_by(User, email: login) || Repo.get_by(User, username: login)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Registers an invited member from `%{username, password, email?}` and confirms
  them immediately — possession of the single-use invite token proves the invite
  was for them (same justification as a magic-link login).
  """
  def register_invited_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, user} -> confirm_user(user)
      other -> other
    end
  end
```

Keep the existing private `confirm_user/1`.

- [ ] **Step 5: Run it to verify it passes**

Run: `mix test test/argus/accounts_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/argus/accounts.ex test/argus/accounts_test.exs test/support/fixtures/accounts_fixtures.ex
git commit -m "feat: register_invited_user and username-or-email login resolver

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Invitations — optional email

**Files:**
- Modify: `lib/argus/entities/invitation.ex`
- Modify: `lib/argus/entities.ex` (`invite_member/4`)
- Test: `test/argus/entities_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/argus/entities_test.exs` (inside an appropriate describe, e.g. a new one):

```elixir
  describe "invite_member/4 without an email (QR invite)" do
    test "creates a pending invitation with no email and sends nothing" do
      scope = Argus.EntitiesFixtures.entity_scope_fixture()

      assert {:ok, invitation} =
               Entities.invite_member(scope, nil, "member", fn _enc -> "http://x/" end)

      assert is_nil(invitation.email)
      assert invitation.role == "member"
    end

    test "treats a blank email as no email" do
      scope = Argus.EntitiesFixtures.entity_scope_fixture()
      assert {:ok, invitation} = Entities.invite_member(scope, "", "member")
      assert is_nil(invitation.email)
    end
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/argus/entities_test.exs`
Expected: FAIL — the invitation changeset still requires `email`.

- [ ] **Step 3: Add the new fields to the schema, then relax the changeset**

In `lib/argus/entities/invitation.ex`, add these two fields to `schema "entity_invitations" do` (after `:accepted_at`):

```elixir
    field :reusable, :boolean, default: false
    field :closed_at, :utc_datetime
```

Then replace `changeset/2` with:

```elixir
  @doc false
  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:email, :role, :token, :expires_at, :accepted_at, :reusable, :closed_at])
    |> validate_required([:role, :token, :expires_at])
    |> validate_inclusion(:role, @roles)
    |> maybe_validate_email_format()
    |> unique_constraint([:entity_id, :email], name: :entity_invitations_one_pending_per_email)
    |> unique_constraint(:token)
  end

  defp maybe_validate_email_format(changeset) do
    if get_field(changeset, :email) do
      validate_format(changeset, :email, ~r/^[^@,;\s]+@[^@,;\s]+$/)
    else
      changeset
    end
  end
```

- [ ] **Step 4: Normalize blank email + guard the notifier in `invite_member/4`**

In `lib/argus/entities.ex`, change the body of `invite_member/4` so the `true ->` branch reads:

```elixir
      true ->
        email = if email in [nil, ""], do: nil, else: email

        with {:ok, invitation} <- insert_invitation(entity, inviter, email, role) do
          if url_fun && invitation.email do
            UserNotifier.deliver_entity_invitation(
              invitation.email,
              entity.name,
              invitation.role,
              url_fun.(Invitation.encode_token(invitation.token))
            )
          end

          {:ok, invitation}
        end
```

- [ ] **Step 5: Run it to verify it passes**

Run: `mix test test/argus/entities_test.exs`
Expected: PASS (and the existing "email delivery" tests still pass).

- [ ] **Step 6: Commit**

```bash
git add lib/argus/entities/invitation.ex lib/argus/entities.ex test/argus/entities_test.exs
git commit -m "feat: allow email-less (QR) invitations

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: InvitationController — three accept paths

**Files:**
- Modify (rewrite): `lib/argus_web/controllers/invitation_controller.ex`
- Modify (rewrite): `test/argus_web/controllers/invitation_controller_test.exs`

- [ ] **Step 1: Rewrite the controller test**

Replace the entire contents of `test/argus_web/controllers/invitation_controller_test.exs` with:

```elixir
defmodule ArgusWeb.InvitationControllerTest do
  use ArgusWeb.ConnCase, async: true

  import Argus.AccountsFixtures

  alias Argus.Accounts
  alias Argus.Entities
  alias Argus.Entities.Invitation

  defp pending_invitation(email \\ nil) do
    admin = Argus.EntitiesFixtures.entity_scope_fixture()
    {:ok, invitation} = Entities.invite_member(admin, email, "member")
    %{admin: admin, invitation: invitation, encoded: Invitation.encode_token(invitation.token)}
  end

  test "create-account path registers, confirms, joins, logs in, redirects", %{conn: conn} do
    %{admin: admin, encoded: encoded} = pending_invitation()

    conn =
      post(conn, ~p"/invitations/#{encoded}/accept", %{
        "create" => %{"username" => "brandnew", "password" => "supersecret12"}
      })

    assert redirected_to(conn) == ~p"/entities/#{admin.entity.slug}"
    assert get_session(conn, :user_token)

    user = Accounts.get_user_by_username("brandnew")
    assert user.confirmed_at
    assert Entities.get_membership!(user, admin.entity).role == "member"
  end

  test "log-in-to-accept path joins an existing account", %{conn: conn} do
    existing = username_user_fixture(%{username: "returner"})
    %{admin: admin, encoded: encoded} = pending_invitation()

    conn =
      post(conn, ~p"/invitations/#{encoded}/accept", %{
        "login" => %{"identifier" => "returner", "password" => valid_user_password()}
      })

    assert redirected_to(conn) == ~p"/entities/#{admin.entity.slug}"
    assert get_session(conn, :user_token)
    assert Entities.get_membership!(existing, admin.entity).role == "member"
  end

  test "already-logged-in user joins with one click", %{conn: conn} do
    user = username_user_fixture(%{username: "alreadyin"})
    %{admin: admin, encoded: encoded} = pending_invitation()

    conn =
      conn
      |> log_in_user(user)
      |> post(~p"/invitations/#{encoded}/accept", %{})

    assert redirected_to(conn) == ~p"/entities/#{admin.entity.slug}"
    assert Entities.get_membership!(user, admin.entity).role == "member"
  end

  test "wrong login credentials redirect back to the invite", %{conn: conn} do
    username_user_fixture(%{username: "returner2"})
    %{encoded: encoded} = pending_invitation()

    conn =
      post(conn, ~p"/invitations/#{encoded}/accept", %{
        "login" => %{"identifier" => "returner2", "password" => "wrong password here"}
      })

    assert redirected_to(conn) == ~p"/invitations/#{encoded}"
    refute get_session(conn, :user_token)
  end

  test "an invalid token redirects home without a session", %{conn: conn} do
    conn = post(conn, ~p"/invitations/garbage/accept", %{})
    assert redirected_to(conn) == ~p"/"
    refute get_session(conn, :user_token)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/argus_web/controllers/invitation_controller_test.exs`
Expected: FAIL (controller still does email auto-register; new param shapes unhandled).

- [ ] **Step 3: Rewrite the controller**

Replace the entire contents of `lib/argus_web/controllers/invitation_controller.ex` with:

```elixir
defmodule ArgusWeb.InvitationController do
  use ArgusWeb, :controller

  alias Argus.Accounts
  alias Argus.Entities

  @doc """
  Accepts an invitation. GET-rendered accept page POSTs here with one of:

    * already logged in  -> no extra params; joins the current user
    * create account     -> %{"create" => %{"username", "password", "email"?}}
    * log in to accept   -> %{"login"  => %{"identifier", "password"}}
  """
  def accept(conn, %{"token" => token} = params) do
    with {:ok, invitation} <- Entities.get_invitation_by_encoded_token(token),
         {:ok, user} <- resolve_user(conn, params),
         {:ok, _membership} <- Entities.accept_invitation(user, invitation.token) do
      conn
      |> put_session(:user_return_to, ~p"/entities/#{invitation.entity.slug}")
      |> put_flash(:info, "Welcome to #{invitation.entity.name}!")
      |> ArgusWeb.UserAuth.log_in_user(user)
    else
      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "Those credentials didn't match. Try again.")
        |> redirect(to: ~p"/invitations/#{token}")

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_flash(:error, "Couldn't create your account: #{error_summary(changeset)}")
        |> redirect(to: ~p"/invitations/#{token}")

      {:error, :seat_limit_reached} ->
        conn
        |> put_flash(:error, "That entity is full — ask an admin to free up a seat.")
        |> redirect(to: ~p"/")

      _ ->
        conn
        |> put_flash(:error, "This invitation link is invalid, expired, or already accepted.")
        |> redirect(to: ~p"/")
    end
  end

  defp resolve_user(conn, params) do
    cond do
      scope = conn.assigns[:current_scope] ->
        {:ok, scope.user}

      match?(%{"create" => %{"username" => _, "password" => _}}, params) ->
        Accounts.register_invited_user(params["create"])

      match?(%{"login" => %{"identifier" => _, "password" => _}}, params) ->
        %{"identifier" => id, "password" => pw} = params["login"]

        case Accounts.get_user_by_login_and_password(id, pw) do
          %Accounts.User{} = user -> {:ok, user}
          nil -> {:error, :invalid_credentials}
        end

      true ->
        {:error, :invalid}
    end
  end

  defp error_summary(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
  end
end
```

- [ ] **Step 4: Run it to verify it passes**

Run: `mix test test/argus_web/controllers/invitation_controller_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/argus_web/controllers/invitation_controller.ex test/argus_web/controllers/invitation_controller_test.exs
git commit -m "feat: invitation accept controller with three onboarding paths

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: InvitationLive.Show — render branches + forms

**Files:**
- Modify (rewrite): `lib/argus_web/live/invitation_live/show.ex`
- Modify (rewrite): `test/argus_web/live/invitation_live_test.exs`

- [ ] **Step 1: Rewrite the LiveView test**

Replace the entire contents of `test/argus_web/live/invitation_live_test.exs` with:

```elixir
defmodule ArgusWeb.InvitationLiveTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Argus.AccountsFixtures

  alias Argus.Accounts
  alias Argus.Entities
  alias Argus.Entities.Invitation

  defp pending_invitation do
    admin = Argus.EntitiesFixtures.entity_scope_fixture()
    {:ok, invitation} = Entities.invite_member(admin, nil, "member")
    %{admin: admin, encoded: Invitation.encode_token(invitation.token)}
  end

  test "invalid token shows a not-valid message", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/invitations/garbage")
    assert html =~ "not valid"
  end

  test "logged-out page shows entity, role, create and login forms with no side effects",
       %{conn: conn} do
    %{admin: admin, encoded: encoded} = pending_invitation()

    {:ok, view, html} = live(conn, ~p"/invitations/#{encoded}")

    assert html =~ admin.entity.name
    assert html =~ "member"
    assert has_element?(view, "form#create-form")
    assert has_element?(view, "form#login-form")

    # Viewing must not create anyone or any membership.
    assert Entities.list_entity_members(admin.entity) |> length() == 1
  end

  test "logged-in user sees a one-click accept form", %{conn: conn} do
    user = username_user_fixture()
    %{encoded: encoded} = pending_invitation()

    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/invitations/#{encoded}")

    assert has_element?(view, "form#accept-form")
    refute has_element?(view, "form#create-form")
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/argus_web/live/invitation_live_test.exs`
Expected: FAIL (current Show renders a single accept form, not create/login branches).

- [ ] **Step 3: Rewrite the LiveView**

Replace the entire contents of `lib/argus_web/live/invitation_live/show.ex` with:

```elixir
defmodule ArgusWeb.InvitationLive.Show do
  use ArgusWeb, :live_view

  alias Argus.Entities

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-md">
        <%= if @invitation do %>
          <.header class="text-center">
            Join {@invitation.entity.name}
            <:subtitle>You've been invited as <b>{@invitation.role}</b>.</:subtitle>
          </.header>

          <%= if @current_scope do %>
            <.form for={@accept_form} id="accept-form" action={~p"/invitations/#{@token}/accept"} class="mt-6">
              <.button class="btn btn-primary w-full" phx-disable-with="Joining...">
                Accept invitation
              </.button>
            </.form>
          <% else %>
            <.form for={@create_form} id="create-form" action={~p"/invitations/#{@token}/accept"} class="mt-6 space-y-2">
              <p class="font-semibold">New here? Create your login</p>
              <.input field={@create_form[:username]} label="Username" autocomplete="username" required />
              <.input field={@create_form[:password]} type="password" label="Password" autocomplete="new-password" required />
              <.input field={@create_form[:email]} type="email" label="Email (optional)" autocomplete="email" />
              <.button class="btn btn-primary w-full" phx-disable-with="Creating...">
                Create account & join
              </.button>
            </.form>

            <div class="divider">or</div>

            <.form for={@login_form} id="login-form" action={~p"/invitations/#{@token}/accept"} class="space-y-2">
              <p class="font-semibold">Already have an account?</p>
              <.input field={@login_form[:identifier]} label="Username or email" autocomplete="username" required />
              <.input field={@login_form[:password]} type="password" label="Password" autocomplete="current-password" required />
              <.button class="btn btn-primary btn-soft w-full" phx-disable-with="Joining...">
                Log in & join
              </.button>
            </.form>
          <% end %>
        <% else %>
          <.header class="text-center">Invitation not valid</.header>
          <p class="mt-4 text-center text-base-content/70">
            This invitation link is invalid, expired, or already accepted.
          </p>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    invitation =
      case Entities.get_invitation_by_encoded_token(token) do
        {:ok, invitation} -> invitation
        :error -> nil
      end

    {:ok,
     assign(socket,
       token: token,
       invitation: invitation,
       accept_form: to_form(%{}, as: "accept"),
       create_form: to_form(%{}, as: "create"),
       login_form: to_form(%{}, as: "login")
     )}
  end
end
```

> The forms use `action=` with **no `phx-submit`**, so submitting does a normal browser POST to the controller — GET stays side-effect-free, and `<.form>` injects the CSRF token automatically.

- [ ] **Step 4: Run it to verify it passes**

Run: `mix test test/argus_web/live/invitation_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/argus_web/live/invitation_live/show.ex test/argus_web/live/invitation_live_test.exs
git commit -m "feat: invitation accept page with create/login/one-click branches

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Login accepts username-or-email

**Files:**
- Modify: `lib/argus_web/controllers/user_session_controller.ex`
- Modify: `lib/argus_web/live/user_live/login.ex`
- Test: `test/argus_web/controllers/user_session_controller_test.exs` (or the existing login test file)

- [ ] **Step 1: Write the failing test**

Add to `test/argus_web/controllers/user_session_controller_test.exs` (create the describe if needed):

```elixir
  describe "POST /users/log-in with username" do
    import Argus.AccountsFixtures

    test "logs in a username+password user", %{conn: conn} do
      user = username_user_fixture(%{username: "loginbox"})

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"identifier" => "loginbox", "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
    end
  end
```

If `test/argus_web/controllers/user_session_controller_test.exs` does not exist, add the `describe` block inside the existing login test module instead (find it with `grep -rl "log-in" test/argus_web`).

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/argus_web/controllers/user_session_controller_test.exs`
Expected: FAIL — the create clause expects `"email"`, not `"identifier"`.

- [ ] **Step 3: Update the session controller**

In `lib/argus_web/controllers/user_session_controller.ex`, replace the `# email + password login` clause with:

```elixir
  # username-or-email + password login
  defp create(conn, %{"user" => user_params}, info) do
    %{"identifier" => identifier, "password" => password} = user_params

    if user = Accounts.get_user_by_login_and_password(identifier, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      # Don't disclose whether the handle is registered.
      conn
      |> put_flash(:error, "Invalid username/email or password")
      |> put_flash(:identifier, String.slice(identifier, 0, 160))
      |> redirect(to: ~p"/users/log-in")
    end
  end
```

- [ ] **Step 4: Update the login form field**

In `lib/argus_web/live/user_live/login.ex`:

(a) In the password form (`id="login_form_password"`), replace the email `<.input>` with:

```elixir
          <.input
            readonly={!!@current_scope}
            field={f[:identifier]}
            type="text"
            label="Email or username"
            autocomplete="username"
            spellcheck="false"
            required
          />
```

(b) In `mount/3`, replace the `form =` line so the prefill key is `identifier`:

```elixir
    identifier =
      Phoenix.Flash.get(socket.assigns.flash, :identifier) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => identifier, "identifier" => identifier}, as: "user")
```

(The magic-link form keeps using `f[:email]`; the password form uses `f[:identifier]`. Both keys live in the one form map.)

- [ ] **Step 5: Run it to verify it passes**

Run: `mix test test/argus_web/controllers/user_session_controller_test.exs`
Expected: PASS.

- [ ] **Step 6: Run the existing auth tests to catch regressions**

Run: `mix test test/argus_web`
Expected: PASS. If a magic-link or email+password test asserted the old `"email"` param or `:email` flash, update it to `"identifier"`/`:identifier`.

- [ ] **Step 7: Commit**

```bash
git add lib/argus_web/controllers/user_session_controller.ex lib/argus_web/live/user_live/login.ex test/argus_web/controllers/user_session_controller_test.exs
git commit -m "feat: password login accepts username or email

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: Membership invite UI — allow QR / email-optional invite

**Files:**
- Modify: `lib/argus_web/live/membership_live/index.ex`
- Test: `test/argus_web/live/membership_live_test.exs`

> The invite form currently requires an email. This task makes email optional and surfaces the shareable invite link/QR for email-less invites. Inspect the current form first (`mix test` + read the file); the steps below assume the existing `invite` handler shape.

- [ ] **Step 1: Write the failing test**

Add to `test/argus_web/live/membership_live_test.exs`, in the admin describe:

```elixir
    test "admin can create an email-less invite and see the shareable link", %{conn: conn} do
      scope = Argus.EntitiesFixtures.entity_scope_fixture()
      conn = log_in_user(conn, scope.user)

      {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}/members")

      html =
        view
        |> form("#invite-form", %{"invite" => %{"email" => "", "role" => "member"}})
        |> render_submit()

      assert html =~ "/invitations/"
    end
```

Adjust the form id / param keys to match the actual template if they differ.

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/argus_web/live/membership_live_test.exs`
Expected: FAIL — blank email rejected or link not shown.

- [ ] **Step 3: Update the invite handler**

In `lib/argus_web/live/membership_live/index.ex`, in the `handle_event("invite", ...)` (or equivalently named) clause, ensure it:
- passes the email through (`invite_member/4` already normalizes blank → nil), and
- on `{:ok, invitation}` builds and assigns the shareable URL so the template can show it (and a QR if desired):

```elixir
        {:ok, invitation} ->
          link = url(~p"/invitations/#{Argus.Entities.Invitation.encode_token(invitation.token)}")

          {:noreply,
           socket
           |> assign(:last_invite_link, link)
           |> put_flash(:info, invite_flash(invitation))
           |> assign_invitations()}
```

Add a small helper:

```elixir
  defp invite_flash(%{email: nil}), do: "Invitation created. Share the link below."
  defp invite_flash(%{email: email}), do: "Invitation sent to #{email}."
```

In the template, render the link when present:

```heex
        <div :if={@last_invite_link} class="alert alert-info mt-2 break-all">
          {@last_invite_link}
        </div>
```

Initialize `:last_invite_link` to `nil` in `mount/3` (add `|> assign(:last_invite_link, nil)` to the socket pipeline). Make the email `<.input>` in the invite form **not** `required`.

- [ ] **Step 4: Run it to verify it passes**

Run: `mix test test/argus_web/live/membership_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/argus_web/live/membership_live/index.ex test/argus_web/live/membership_live_test.exs
git commit -m "feat: email-optional member invites with shareable link

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: Reusable-session validity + non-consuming accept

**Files:**
- Modify: `lib/argus/entities.ex` (`fetch_pending_invitation`, `accept_invitation_multi`)
- Modify: `lib/argus/entities/membership.ex` (add unique_constraint)
- Test: `test/argus/entities_test.exs`

> Confirm the PubSub name first: `grep -n "PubSub" lib/argus/application.ex` (used in Task 10). Likely `Argus.PubSub`.

- [ ] **Step 1: Write the failing test**

Add to `test/argus/entities_test.exs`:

```elixir
  describe "reusable invite sessions" do
    alias Argus.Accounts
    import Argus.AccountsFixtures

    defp open_session(role \\ "member") do
      admin = Argus.EntitiesFixtures.entity_scope_fixture()
      {:ok, inv} = Entities.open_invite_session(admin, role)
      %{admin: admin, inv: inv}
    end

    test "two different users can accept the same reusable token" do
      %{admin: admin, inv: inv} = open_session()
      u1 = username_user_fixture()
      u2 = username_user_fixture()

      assert {:ok, m1} = Entities.accept_invitation(u1, inv.token)
      assert m1.role == "member"
      assert {:ok, _m2} = Entities.accept_invitation(u2, inv.token)

      # token is still live (not consumed)
      assert {:ok, _} = Entities.get_invitation_by_encoded_token(Argus.Entities.Invitation.encode_token(inv.token))
      assert Entities.list_entity_members(admin.entity) |> length() == 3
    end

    test "a re-accept by an existing member is a no-op success" do
      %{inv: inv} = open_session()
      u1 = username_user_fixture()
      {:ok, _} = Entities.accept_invitation(u1, inv.token)
      assert {:ok, :already_member} = Entities.accept_invitation(u1, inv.token)
    end

    test "a closed session rejects new accepts" do
      %{admin: admin, inv: inv} = open_session()
      {:ok, _} = Entities.close_invite_session(admin, inv.id)
      u = username_user_fixture()
      assert {:error, :closed} = Entities.accept_invitation(u, inv.token)
    end
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/argus/entities_test.exs`
Expected: FAIL — `open_invite_session/2`, `close_invite_session/2` undefined; second accept consumes/duplicates.

- [ ] **Step 3: Add a unique_constraint to the membership changeset**

In `lib/argus/entities/membership.ex`, in `changeset/2`, after the existing validations add:

```elixir
    |> unique_constraint([:user_id, :entity_id])
```

- [ ] **Step 4: Branch `fetch_pending_invitation` and `accept_invitation_multi` on `reusable`**

In `lib/argus/entities.ex`, replace `fetch_pending_invitation/1` with:

```elixir
  defp fetch_pending_invitation(token) do
    case Repo.get_by(Invitation, token: token) do
      %Invitation{} = invitation -> validate_invitation_live(invitation)
      nil -> {:error, :not_found}
    end
  end

  defp validate_invitation_live(%Invitation{reusable: true} = inv) do
    cond do
      not is_nil(inv.closed_at) -> {:error, :closed}
      invitation_expired?(inv) -> {:error, :expired}
      true -> {:ok, Repo.preload(inv, :entity)}
    end
  end

  defp validate_invitation_live(%Invitation{reusable: false} = inv) do
    cond do
      not is_nil(inv.accepted_at) -> {:error, :already_accepted}
      invitation_expired?(inv) -> {:error, :expired}
      true -> {:ok, Repo.preload(inv, :entity)}
    end
  end

  defp invitation_expired?(%Invitation{expires_at: ea}) do
    DateTime.compare(DateTime.utc_now(:second), ea) != :lt
  end
```

Then replace `accept_invitation_multi/2` with:

```elixir
  defp accept_invitation_multi(user, %Invitation{} = invitation) do
    now = DateTime.utc_now(:second)

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:membership, fn _ ->
        %Membership{
          user_id: user.id,
          entity_id: invitation.entity_id,
          role: invitation.role,
          invited_by_id: invitation.invited_by_id,
          accepted_at: now,
          is_default: first_entity_for_user?(user)
        }
        |> Membership.changeset(%{})
      end)

    multi =
      if invitation.reusable do
        multi
      else
        Ecto.Multi.update(multi, :invitation, Invitation.changeset(invitation, %{accepted_at: now}))
      end

    multi
    |> Repo.transaction()
    |> case do
      {:ok, %{membership: membership}} ->
        membership = Repo.preload(membership, :user)

        Phoenix.PubSub.broadcast(
          Argus.PubSub,
          "entity:#{invitation.entity_id}:members",
          {:member_joined, membership}
        )

        {:ok, membership}

      {:error, :membership, %Ecto.Changeset{} = changeset, _} ->
        if Enum.any?(changeset.errors, fn {_f, {_m, opts}} -> opts[:constraint] == :unique end) do
          {:ok, :already_member}
        else
          {:error, changeset}
        end

      {:error, :invitation, changeset, _} ->
        {:error, changeset}
    end
  end
```

- [ ] **Step 5: Add `open_invite_session/2` and `close_invite_session/2`**

In `lib/argus/entities.ex`, add (near `invite_member/4`):

```elixir
  @doc """
  Opens a reusable, admin-supervised invite session for `role` ("manager" or
  "member"). Auto-expires 30 minutes from now; close early with
  `close_invite_session/2`.
  """
  def open_invite_session(%Scope{user: inviter, entity: entity} = scope, role) do
    cond do
      not Authorization.can?(scope, :manage_entity) ->
        :not_authorise

      role not in ["manager", "member"] ->
        {:error, :invalid_role}

      true ->
        token = :crypto.strong_rand_bytes(32)
        expires_at = DateTime.add(DateTime.utc_now(:second), 30 * 60, :second)

        %Invitation{entity_id: entity.id, invited_by_id: inviter.id}
        |> Invitation.changeset(%{
          role: role,
          token: token,
          expires_at: expires_at,
          reusable: true
        })
        |> Repo.insert()
    end
  end

  @doc """
  Closes a reusable invite session (admin-only). Stamps `closed_at`.
  """
  def close_invite_session(%Scope{} = scope, invitation_id) do
    if Authorization.can?(scope, :manage_entity) do
      case Repo.get_by(Invitation, id: invitation_id, entity_id: scope.entity.id, reusable: true) do
        nil ->
          {:error, :not_found}

        invitation ->
          invitation
          |> Invitation.changeset(%{closed_at: DateTime.utc_now(:second)})
          |> Repo.update()
      end
    else
      :not_authorise
    end
  end
```

- [ ] **Step 6: Run it to verify it passes**

Run: `mix test test/argus/entities_test.exs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/argus/entities.ex lib/argus/entities/membership.ex test/argus/entities_test.exs
git commit -m "feat: reusable invite sessions (open/close, non-consuming accept)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 10: QR rendering helper

**Files:**
- Modify: `mix.exs` (add `eqrcode`)
- Create: `lib/argus_web/qr.ex`
- Test: `test/argus_web/qr_test.exs`

- [ ] **Step 1: Add the dependency**

In `mix.exs`, add to `deps/0`:

```elixir
      {:eqrcode, "~> 0.2"},
```

Run: `mix deps.get`
Expected: fetches `eqrcode`.

- [ ] **Step 2: Write the failing test**

Create `test/argus_web/qr_test.exs`:

```elixir
defmodule ArgusWeb.QRTest do
  use ExUnit.Case, async: true

  test "svg/1 returns an inline SVG string for a URL" do
    svg = ArgusWeb.QR.svg("https://example.com/invitations/abc")
    assert is_binary(svg)
    assert svg =~ "<svg"
  end
end
```

- [ ] **Step 3: Run it to verify it fails**

Run: `mix test test/argus_web/qr_test.exs`
Expected: FAIL — `ArgusWeb.QR` undefined.

- [ ] **Step 4: Implement the helper**

Create `lib/argus_web/qr.ex`:

```elixir
defmodule ArgusWeb.QR do
  @moduledoc "Renders a URL as an inline SVG QR code."

  @doc "Returns an SVG string (no XML declaration) for embedding with `raw/1`."
  def svg(url, opts \\ []) when is_binary(url) do
    width = Keyword.get(opts, :width, 240)

    url
    |> EQRCode.encode()
    |> EQRCode.svg(width: width, viewbox: true)
  end
end
```

- [ ] **Step 5: Run it to verify it passes**

Run: `mix test test/argus_web/qr_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mix.exs mix.lock lib/argus_web/qr.ex test/argus_web/qr_test.exs
git commit -m "feat: inline SVG QR code helper

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 11: Admin invite-session LiveView (QR + live roster + close)

**Files:**
- Create: `lib/argus_web/live/membership_live/invite_session.ex`
- Modify: `lib/argus_web/router.ex` (add route in the `:entity_scoped` live_session)
- Test: `test/argus_web/live/invite_session_live_test.exs`

- [ ] **Step 1: Add the route**

In `lib/argus_web/router.ex`, inside `live_session :entity_scoped ... do`, after the `members` line add:

```elixir
      live "/entities/:entity_slug/invite-session/:role", MembershipLive.InviteSession, :show
```

- [ ] **Step 2: Write the failing test**

Create `test/argus_web/live/invite_session_live_test.exs`:

```elixir
defmodule ArgusWeb.InviteSessionLiveTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Argus.AccountsFixtures

  alias Argus.Entities

  test "admin opens a member session: sees QR and a live roster updates", %{conn: conn} do
    scope = Argus.EntitiesFixtures.entity_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, html} = live(conn, ~p"/entities/#{scope.entity.slug}/invite-session/member")

    assert html =~ "<svg"
    assert html =~ "/invitations/"

    # Simulate a scanner finishing registration in another process.
    joiner = username_user_fixture(%{username: "scannerjoe"})
    inv = Argus.Repo.get_by!(Entities.Invitation, entity_id: scope.entity.id, reusable: true)
    {:ok, _} = Entities.accept_invitation(joiner, inv.token)

    assert render(view) =~ "scannerjoe"
  end

  test "a non-admin cannot open a session", %{conn: conn} do
    member = member_scope_fixture()
    conn = log_in_user(conn, member.user)

    assert {:error, {:redirect, _}} =
             live(conn, ~p"/entities/#{member.entity.slug}/invite-session/member")
  end
end
```

- [ ] **Step 3: Run it to verify it fails**

Run: `mix test test/argus_web/live/invite_session_live_test.exs`
Expected: FAIL — `MembershipLive.InviteSession` undefined.

- [ ] **Step 4: Implement the LiveView**

Create `lib/argus_web/live/membership_live/invite_session.ex`:

```elixir
defmodule ArgusWeb.MembershipLive.InviteSession do
  use ArgusWeb, :live_view

  alias Argus.Entities

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-md text-center">
        <.header>
          Invite {@role}s
          <:subtitle>Scan to join {@current_scope.entity.name}. Closes automatically in 30 min.</:subtitle>
        </.header>

        <%= if @closed do %>
          <p class="alert alert-info mt-6">Session closed.</p>
          <.link navigate={~p"/entities/#{@current_scope.entity.slug}/members"} class="btn mt-4">
            Back to members
          </.link>
        <% else %>
          <div class="mt-6 flex justify-center">{raw(@qr)}</div>
          <p class="mt-2 break-all text-sm text-base-content/70">{@link}</p>

          <button phx-click="close" class="btn btn-error btn-soft mt-4" phx-disable-with="Closing...">
            Close session
          </button>

          <div class="mt-8 text-left">
            <p class="font-semibold">Joined so far ({@count})</p>
            <ul id="roster" phx-update="stream" class="mt-2 space-y-1">
              <li :for={{id, m} <- @streams.roster} id={id} class="badge badge-soft">
                {m.user.username || m.user.email}
              </li>
            </ul>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"role" => role}, _session, socket) do
    scope = socket.assigns.current_scope

    case Entities.open_invite_session(scope, role) do
      {:ok, invitation} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Argus.PubSub, "entity:#{scope.entity.id}:members")
        end

        link = url(~p"/invitations/#{Entities.Invitation.encode_token(invitation.token)}")

        {:ok,
         socket
         |> assign(role: role, invitation: invitation, link: link, qr: ArgusWeb.QR.svg(link),
           closed: false, count: 0)
         |> stream(:roster, [])}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "You can't open an invite session.")
         |> push_navigate(to: ~p"/entities/#{scope.entity.slug}/members")}
    end
  end

  @impl true
  def handle_event("close", _params, socket) do
    Entities.close_invite_session(socket.assigns.current_scope, socket.assigns.invitation.id)
    {:noreply, assign(socket, :closed, true)}
  end

  @impl true
  def handle_info({:member_joined, membership}, socket) do
    {:noreply,
     socket
     |> stream_insert(:roster, membership, at: 0)
     |> update(:count, &(&1 + 1))}
  end
end
```

> `:require_authenticated` + `:require_entity` on-mounts already guard the route; `open_invite_session/2` enforces `:manage_entity`, so a non-admin is redirected (the test asserts the redirect).

- [ ] **Step 5: Run it to verify it passes**

Run: `mix test test/argus_web/live/invite_session_live_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/argus_web/live/membership_live/invite_session.ex lib/argus_web/router.ex test/argus_web/live/invite_session_live_test.exs
git commit -m "feat: admin invite-session LiveView with QR and live roster

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 12: Members screen — Start QR invite buttons

**Files:**
- Modify: `lib/argus_web/live/membership_live/index.ex` (template)
- Test: `test/argus_web/live/membership_live_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/argus_web/live/membership_live_test.exs` (admin describe):

```elixir
    test "admin sees Start manager/member QR invite links", %{conn: conn} do
      scope = Argus.EntitiesFixtures.entity_scope_fixture()
      conn = log_in_user(conn, scope.user)
      {:ok, _view, html} = live(conn, ~p"/entities/#{scope.entity.slug}/members")

      assert html =~ ~p"/entities/#{scope.entity.slug}/invite-session/manager"
      assert html =~ ~p"/entities/#{scope.entity.slug}/invite-session/member"
    end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/argus_web/live/membership_live_test.exs`
Expected: FAIL — links absent.

- [ ] **Step 3: Add the buttons to the Members template**

In `lib/argus_web/live/membership_live/index.ex`, in the render template near the invite form, add (admin-only — wrap in the existing manage check if there is one):

```heex
      <div class="mt-4 flex gap-2">
        <.link
          navigate={~p"/entities/#{@current_scope.entity.slug}/invite-session/manager"}
          class="btn btn-outline btn-sm"
        >
          <.icon name="hero-qr-code" class="size-4" /> Manager QR
        </.link>
        <.link
          navigate={~p"/entities/#{@current_scope.entity.slug}/invite-session/member"}
          class="btn btn-outline btn-sm"
        >
          <.icon name="hero-qr-code" class="size-4" /> Member QR
        </.link>
      </div>
```

- [ ] **Step 4: Run it to verify it passes**

Run: `mix test test/argus_web/live/membership_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/argus_web/live/membership_live/index.ex test/argus_web/live/membership_live_test.exs
git commit -m "feat: Start manager/member QR invite from Members screen

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 13: Full suite + precommit

**Files:** none (verification)

- [ ] **Step 1: Run the whole suite**

Run: `mix test`
Expected: all green. Fix any regression where an old test assumed email-only identity or the old auto-register accept flow.

- [ ] **Step 2: Run precommit**

Run: `mix precommit`
Expected: compile (warnings-as-errors) clean, `deps.unlock --unused` clean, formatted, tests pass.

- [ ] **Step 3: Final commit (only if precommit changed anything, e.g. formatting)**

```bash
git add -A
git commit -m "chore: precommit cleanup for username onboarding

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review notes (for the implementer)

- **Spec coverage:** username + nullable email + check constraint + session columns (T1); registration_changeset (T2); register_invited_user + login resolver (T3); optional invitation email + invitation fields (T4); three accept paths + `{:ok, :already_member}` success (T5); accept-page branches (T6); username-or-email login (T7); email-optional single-use invite UI (T8); reusable-session validity/open/close + non-consuming accept + PubSub (T9); QR helper (T10); admin invite-session LiveView with live roster (T11); Members-screen QR buttons for manager/member (T12); suite+precommit (T13). All spec sections map to a task.
- **Type consistency:** controller reads `params["create"]` / `params["login"]`; Show forms use `as: "create"` / `as: "login"` / `as: "accept"`; login uses `user_params["identifier"]` with form field `f[:identifier]` (T5–T7). `accept_invitation/2` returns `{:ok, membership}` **or** `{:ok, :already_member}` — both matched by the controller's `{:ok, _}` success clause (T5/T9). Session role is `"manager"`/`"member"` only across T9/T11/T12.
- **PubSub name:** the plan assumes `Argus.PubSub` — confirm against `lib/argus/application.ex` before T9/T11 and adjust if different.
- **Out of scope (do not build):** phone, OTP, self-service reset, passkeys, per-user approval gating (sessions are passive), admin-role QR sessions.
