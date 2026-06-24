defmodule ArgusWeb.LegacyAuthRedirectControllerTest do
  use ArgusWeb.ConnCase, async: true

  @mobile_ua "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"

  test "GET /m/users/register redirects to unified register", %{conn: conn} do
    conn = get(conn, ~p"/m/users/register")
    assert redirected_to(conn) == ~p"/users/register"
  end

  test "GET /m/users/log-in redirects to unified log-in", %{conn: conn} do
    conn = get(conn, ~p"/m/users/log-in")
    assert redirected_to(conn) == ~p"/users/log-in"
  end

  test "GET /m/users/log-in/:token redirects to unified confirmation", %{conn: conn} do
    conn = get(conn, ~p"/m/users/log-in/some-token")
    assert redirected_to(conn) == ~p"/users/log-in/some-token"
  end

  test "legacy register redirect works with mobile UA through full router", %{conn: conn} do
    conn =
      conn
      |> put_req_header("user-agent", @mobile_ua)
      |> get(~p"/m/users/register")

    assert redirected_to(conn) == ~p"/users/register"
  end
end
