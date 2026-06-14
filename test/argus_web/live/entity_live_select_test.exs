defmodule ArgusWeb.EntityLiveSelectTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Argus.Entities

  @mobile_ua "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"

  setup :register_and_log_in_user

  defp mobile_conn(conn, scope) do
    conn |> log_in_user(scope.user) |> put_req_header("user-agent", @mobile_ua)
  end

  test "user menu links to all entities picker", %{conn: conn} do
    scope = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, html} =
      live(conn, ~p"/entities/#{scope.entity.slug}")

    assert html =~ ~s|href="/entities?pick=1"|
    assert has_element?(view, "a[href='/entities?pick=1']", "All entities")
  end

  test "pick=1 shows entity picker when user has multiple entities", %{conn: conn} do
    scope = Argus.EntitiesFixtures.manager_scope_fixture()

    {:ok, _} =
      Entities.create_entity(scope, %{slug: "beta-corp", name: "Beta Corp"})

    conn = log_in_user(conn, scope.user)

    {:ok, _view, html} = live(conn, ~p"/entities?pick=1")
    assert html =~ "Your entities"
    assert html =~ "Beta Corp"
  end

  test "pick=1 shows picker even for a single entity", %{conn: conn} do
    scope = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, _view, html} = live(conn, ~p"/entities?pick=1")
    assert html =~ "Your entities"
    assert html =~ scope.entity.name
  end

  test "mobile picker uses mobile shell and links to /m routes", %{conn: conn} do
    scope = Argus.EntitiesFixtures.manager_scope_fixture()

    {:ok, other} =
      Entities.create_entity(scope, %{slug: "beta-corp", name: "Beta Corp"})

    conn = mobile_conn(conn, scope)

    {:ok, view, html} = live(conn, ~p"/m/entities?pick=1")

    assert html =~ "Your entities"
    assert html =~ "Beta Corp"
    assert has_element?(view, "a[href='/m/#{other.slug}']", "Enter")
    refute has_element?(view, "#more-sheet")
  end

  test "mobile UA is redirected from desktop picker to mobile picker", %{conn: conn} do
    scope = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, scope)

    conn = get(conn, ~p"/entities?pick=1")
    assert redirected_to(conn) == "/m/entities?pick=1"
  end
end
