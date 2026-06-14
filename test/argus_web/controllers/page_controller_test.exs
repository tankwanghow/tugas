defmodule ArgusWeb.PageControllerTest do
  use ArgusWeb.ConnCase

  test "GET / shows the marketing page when logged out", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "Never miss a"
    assert html =~ "deadline"
    assert html =~ "Start tracking free"
    assert html =~ "A vigilance layer over every obligation"
    assert html =~ ~p"/users/register"
    assert html =~ ~p"/users/log-in"
  end

  test "GET / redirects a logged-in user to their workspace", %{conn: conn} do
    user = Argus.AccountsFixtures.user_fixture()
    conn = conn |> log_in_user(user) |> get(~p"/")
    assert redirected_to(conn) == ~p"/entities"
  end
end
