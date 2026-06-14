defmodule ArgusWeb.MobileLiveTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Argus.ObligationsFixtures

  alias Argus.Obligations

  @mobile_ua "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"

  setup :register_and_log_in_user

  defp mobile_conn(conn, scope) do
    conn |> log_in_user(scope.user) |> put_req_header("user-agent", @mobile_ua)
  end

  test "mobile dashboard renders live cycles", %{conn: conn} do
    {scope, obligation} = assigned_member_scope_fixture()
    conn = mobile_conn(conn, scope)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}")

    assert has_element?(view, "#mobile-obligations")
    assert has_element?(view, "#m-ob-#{obligation.id}")
  end

  test "mobile show runs start_progress workflow", %{conn: conn} do
    {scope, obligation} = assigned_member_scope_fixture()
    conn = mobile_conn(conn, scope)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#m-start-progress-btn") |> render_click()
    assert render(view) =~ "in_progress"
  end

  test "mobile cancel modal requires a reason", %{conn: conn} do
    {scope, obligation} = manager_obligation_scope_fixture()
    conn = mobile_conn(conn, scope)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#m-cancel-btn") |> render_click()
    assert has_element?(view, "#m-cancel-modal")

    view |> form("#m-cancel-form", %{"cancel" => %{"note" => ""}}) |> render_submit()
    assert render(view) =~ "A reason is required"
  end

  test "mobile done modal requires next due for recurring", %{conn: conn} do
    {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")
    conn = mobile_conn(conn, scope)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#m-done-btn") |> render_click()
    view |> form("#m-done-form", %{"done" => %{"next_due_by" => ""}}) |> render_submit()

    assert render(view) =~ "Next due date is required"
  end

  test "completing on mobile spawns successor and redirects to list", %{conn: conn} do
    {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")
    conn = mobile_conn(conn, scope)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#m-done-btn") |> render_click()
    view |> form("#m-done-form", %{"done" => %{"next_due_by" => "2026-07-15"}}) |> render_submit()

    assert_redirect(view, ~p"/m/#{scope.entity.slug}/obligations")
    refute Obligations.get_obligation!(scope, obligation.id).completed_at == nil
  end

  test "mobile obligations list filters completed cycles", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    member_scope = member_scope_on_entity(manager.entity)
    conn = mobile_conn(conn, member_scope)
    type = type_fixture(manager.entity)

    {:ok, _} =
      Obligations.create_obligation(manager, %{
        title: "Alpha Live",
        obligation_type_id: type.id,
        primary_assignee_id: member_scope.user.id,
        due_by: ~D[2026-06-30]
      })

    {:ok, to_complete} =
      Obligations.create_obligation(manager, %{
        title: "Beta Done",
        obligation_type_id: type.id,
        primary_assignee_id: member_scope.user.id,
        due_by: ~D[2026-05-30]
      })

    assert {:ok, completed, _} = Obligations.complete(member_scope, to_complete, %{})

    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}/obligations")

    view |> element("#m-filter-my_completed") |> render_click()
    assert has_element?(view, "#m-ob-#{completed.id}")
    refute has_element?(view, "#m-obligations-empty")
  end

  test "mobile more sheet links to all entities picker", %{conn: conn} do
    {scope, _} = assigned_member_scope_fixture()
    conn = mobile_conn(conn, scope)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}")

    assert has_element?(view, "a[href='/m/entities?pick=1']", "All entities")
  end

  test "mobile UA is redirected from desktop dashboard to /m", %{conn: conn} do
    {scope, _obligation} = assigned_member_scope_fixture()

    conn =
      conn
      |> log_in_user(scope.user)
      |> put_req_header("user-agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)")
      |> get(~p"/entities/#{scope.entity.slug}")

    assert redirected_to(conn) == ~p"/m/#{scope.entity.slug}"
  end
end
