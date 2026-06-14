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

    view
    |> form("#invite-form", %{"invite" => %{"email" => "new@example.com", "role" => "member"}})
    |> render_submit()

    assert has_element?(view, "#pending-invitations", "new@example.com")
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
end
