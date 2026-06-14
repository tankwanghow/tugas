defmodule ArgusWeb.DashboardLiveTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Argus.ObligationsFixtures

  alias Argus.Obligations

  setup :register_and_log_in_user

  test "member defaults to My work tab", %{conn: conn} do
    {scope, _obligation} = assigned_member_scope_fixture()

    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}")

    assert has_element?(view, "#tab-my-work.tab-active")
    refute has_element?(view, "#tab-team-overview.tab-active")
  end

  test "user menu has all entities link", %{conn: conn} do
    {scope, _} = manager_obligation_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}")

    assert has_element?(view, "a[href='/entities?pick=1']", "All entities")
    refute has_element?(view, "li.menu-title", "Switch entity")
  end

  test "manager defaults to Team overview tab", %{conn: conn} do
    {scope, _obligation} = manager_obligation_scope_fixture()

    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}")

    assert has_element?(view, "#tab-team-overview.tab-active")
  end

  test "switches tabs", %{conn: conn} do
    {scope, _obligation} = manager_obligation_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}")

    view |> element("#tab-my-work") |> render_click()
    assert has_element?(view, "#tab-my-work.tab-active")
  end

  test "overdue obligations render in the overdue tier", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    member = member_fixture(manager.entity)
    type = type_fixture(manager.entity)

    {:ok, _} =
      Obligations.create_obligation(manager, %{
        title: "Late filing",
        obligation_type_id: type.id,
        primary_assignee_id: member.id,
        due_by: ~D[2020-01-01]
      })

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}")

    assert has_element?(view, "[data-tier=overdue]")
    assert has_element?(view, "[data-overdue-count]")
  end
end
