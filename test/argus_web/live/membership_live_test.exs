defmodule ArgusWeb.MembershipLiveTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Argus.ObligationsFixtures

  alias Argus.Entities

  setup :register_and_log_in_user

  test "admin sees members and can invite", %{conn: conn} do
    admin = Argus.EntitiesFixtures.entity_scope_fixture()
    conn = log_in_user(conn, admin.user)
    _member = member_fixture(admin.entity)

    {:ok, view, _html} = live(conn, ~p"/entities/#{admin.entity.slug}/members")

    assert has_element?(view, "#members-list")
    assert has_element?(view, "#invite-form")

    html =
      view
      |> form("#invite-form", %{"invite" => %{"email" => "new@example.com", "role" => "member"}})
      |> render_submit()

    assert has_element?(view, "#pending-invitations", "new@example.com")
    assert html =~ "Invitation sent to new@example.com"
  end

  test "admin can change a member's role", %{conn: conn} do
    admin = Argus.EntitiesFixtures.entity_scope_fixture()
    conn = log_in_user(conn, admin.user)
    member = member_fixture(admin.entity)
    membership = Entities.get_membership!(member, admin.entity)

    {:ok, view, _html} = live(conn, ~p"/entities/#{admin.entity.slug}/members")

    view
    |> element("#member-#{membership.id} form")
    |> render_change(%{"membership_id" => membership.id, "role" => "manager"})

    assert Entities.get_membership!(member, admin.entity).role == "manager"
  end

  test "shows a member's username instead of email when set", %{conn: conn} do
    admin = Argus.EntitiesFixtures.entity_scope_fixture()
    conn = log_in_user(conn, admin.user)
    member = member_fixture(admin.entity)
    {:ok, _} = Argus.Accounts.update_user_username(member, %{"username" => "handle9"})

    {:ok, view, _html} = live(conn, ~p"/entities/#{admin.entity.slug}/members")

    assert has_element?(view, "#members-list", "handle9")
  end

  test "admin disables a member through the confirm modal", %{conn: conn} do
    admin = Argus.EntitiesFixtures.entity_scope_fixture()
    conn = log_in_user(conn, admin.user)
    member = member_fixture(admin.entity)
    membership = Entities.get_membership!(member, admin.entity)

    {:ok, view, _html} = live(conn, ~p"/entities/#{admin.entity.slug}/members")

    view |> element("#disable-member-#{membership.id}") |> render_click()
    assert has_element?(view, "#disable-member-modal")

    view |> element("#confirm-disable") |> render_click()

    assert Entities.get_membership!(member, admin.entity).disabled_at
    assert has_element?(view, "#enable-member-#{membership.id}")
  end

  test "admin re-enables a disabled member", %{conn: conn} do
    admin = Argus.EntitiesFixtures.entity_scope_fixture()
    conn = log_in_user(conn, admin.user)
    member = member_fixture(admin.entity)
    membership = Entities.get_membership!(member, admin.entity)
    {:ok, _} = Entities.disable_member(admin, membership)

    {:ok, view, _html} = live(conn, ~p"/entities/#{admin.entity.slug}/members")

    view |> element("#enable-member-#{membership.id}") |> render_click()

    refute Entities.get_membership!(member, admin.entity).disabled_at
  end

  test "an admin cannot disable themselves (no disable control on own row)", %{conn: conn} do
    admin = Argus.EntitiesFixtures.entity_scope_fixture()
    conn = log_in_user(conn, admin.user)
    own = Entities.get_membership!(admin.user, admin.entity)

    {:ok, view, _html} = live(conn, ~p"/entities/#{admin.entity.slug}/members")

    refute has_element?(view, "#disable-member-#{own.id}")
  end

  test "admin can revoke a pending invitation", %{conn: conn} do
    admin = Argus.EntitiesFixtures.entity_scope_fixture()
    conn = log_in_user(conn, admin.user)

    {:ok, invitation} = Entities.invite_member(admin, "pending@example.com", "member")

    {:ok, view, _html} = live(conn, ~p"/entities/#{admin.entity.slug}/members")

    assert has_element?(view, "#revoke-invite-#{invitation.id}")

    view |> element("#revoke-invite-#{invitation.id}") |> render_click()

    refute has_element?(view, "#pending-invitations", "pending@example.com")
    assert Entities.list_pending_invitations(admin.entity) == []
  end

  test "non-admin does not see management controls", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}/members")

    refute has_element?(view, "#invite-form")
  end

  test "admin sees Start manager/member QR invite links", %{conn: conn} do
    scope = Argus.EntitiesFixtures.entity_scope_fixture()
    conn = log_in_user(conn, scope.user)
    {:ok, _view, html} = live(conn, ~p"/entities/#{scope.entity.slug}/members")

    assert html =~ ~p"/entities/#{scope.entity.slug}/invite-session/manager"
    assert html =~ ~p"/entities/#{scope.entity.slug}/invite-session/member"
  end

  test "admin can create an email-less invite and see the shareable link", %{conn: conn} do
    scope = Argus.EntitiesFixtures.entity_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}/members")

    view
    |> form("#invite-form", %{"invite" => %{"email" => "", "role" => "member"}})
    |> render_submit()

    assert has_element?(view, "#invite-link a[href*='/invitations/']")
  end
end
