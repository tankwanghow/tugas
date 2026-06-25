defmodule ArgusWeb.Plugs.AutoRouteByDeviceTest do
  use ArgusWeb.ConnCase, async: true

  alias ArgusWeb.Plugs.AutoRouteByDevice

  @mobile_ua "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"

  setup %{conn: conn} do
    {:ok, conn: conn |> init_test_session(%{})}
  end

  describe "mobile_capable_tails/0" do
    test "desktop-only paths are absent from the whitelist" do
      tails = AutoRouteByDevice.mobile_capable_tails()

      assert "/obligations/new" in tails
      assert "/obligation-types" in tails
      assert "/todos" in tails
      assert "/todos/new" in tails
      refute "/members" in tails
    end
  end

  describe "call/2" do
    test "redirects mobile UA from desktop dashboard to mobile", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", @mobile_ua)
        |> Map.put(:request_path, "/entities/acme")
        |> Map.put(:path_info, ["entities", "acme"])
        |> Map.put(:query_string, "")
        |> AutoRouteByDevice.call([])

      assert redirected_to(conn) == "/m/acme"
      assert conn.halted
    end

    test "redirects mobile UA from desktop new-obligation form to mobile", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", @mobile_ua)
        |> Map.put(:request_path, "/entities/acme/obligations/new")
        |> Map.put(:path_info, ["entities", "acme", "obligations", "new"])
        |> Map.put(:query_string, "")
        |> AutoRouteByDevice.call([])

      assert redirected_to(conn) == "/m/acme/obligations/new"
      assert conn.halted
    end

    test "redirects mobile UA from desktop obligation show to mobile", %{conn: conn} do
      id = Ecto.UUID.generate()

      conn =
        conn
        |> put_req_header("user-agent", @mobile_ua)
        |> Map.put(:request_path, "/entities/acme/obligations/#{id}")
        |> Map.put(:path_info, ["entities", "acme", "obligations", id])
        |> Map.put(:query_string, "")
        |> AutoRouteByDevice.call([])

      assert redirected_to(conn) == "/m/acme/obligations/#{id}"
      assert conn.halted
    end

    test "redirects mobile UA from desktop obligation create to mobile", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", @mobile_ua)
        |> Map.put(:request_path, "/entities/acme/obligations/new")
        |> Map.put(:path_info, ["entities", "acme", "obligations", "new"])
        |> Map.put(:query_string, "")
        |> AutoRouteByDevice.call([])

      assert redirected_to(conn) == "/m/acme/obligations/new"
      assert conn.halted
    end

    test "does not redirect mobile UA on unified auth paths", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", @mobile_ua)
        |> Map.put(:request_path, "/users/register")
        |> Map.put(:path_info, ["users", "register"])
        |> Map.put(:query_string, "")
        |> AutoRouteByDevice.call([])

      refute conn.halted
    end

    test "redirects mobile UA from desktop obligation types to mobile", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", @mobile_ua)
        |> Map.put(:request_path, "/entities/acme/obligation-types")
        |> Map.put(:path_info, ["entities", "acme", "obligation-types"])
        |> Map.put(:query_string, "")
        |> AutoRouteByDevice.call([])

      assert redirected_to(conn) == "/m/acme/obligation-types"
      assert conn.halted
    end

    test "redirects desktop UA from mobile obligation types to desktop", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X)")
        |> Map.put(:request_path, "/m/acme/obligation-types")
        |> Map.put(:path_info, ["m", "acme", "obligation-types"])
        |> Map.put(:query_string, "")
        |> AutoRouteByDevice.call([])

      assert redirected_to(conn) == "/entities/acme/obligation-types"
      assert conn.halted
    end

    test "does not redirect mobile UA on desktop-only members page", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", @mobile_ua)
        |> Map.put(:request_path, "/entities/acme/members")
        |> Map.put(:path_info, ["entities", "acme", "members"])
        |> Map.put(:query_string, "")
        |> AutoRouteByDevice.call([])

      refute conn.halted
    end

    test "redirects desktop UA from mobile dashboard to desktop", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X)")
        |> Map.put(:request_path, "/m/acme")
        |> Map.put(:path_info, ["m", "acme"])
        |> Map.put(:query_string, "")
        |> AutoRouteByDevice.call([])

      assert redirected_to(conn) == "/entities/acme"
      assert conn.halted
    end

    test "argus_view=desktop cookie keeps mobile URL on desktop", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", @mobile_ua)
        |> put_req_cookie("argus_view", "desktop")
        |> Map.put(:request_path, "/m/acme")
        |> Map.put(:path_info, ["m", "acme"])
        |> Map.put(:query_string, "")
        |> AutoRouteByDevice.call([])

      assert redirected_to(conn) == "/entities/acme"
      assert conn.halted
    end

    test "does not redirect mobile UA on entity picker alone", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", @mobile_ua)
        |> Map.put(:request_path, "/entities")
        |> Map.put(:path_info, ["entities"])
        |> Map.put(:query_string, "pick=1")
        |> AutoRouteByDevice.call([])

      refute conn.halted
    end

    test "argus_view=mobile cookie forces mobile from desktop", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X)")
        |> put_req_cookie("argus_view", "mobile")
        |> Map.put(:request_path, "/entities/acme")
        |> Map.put(:path_info, ["entities", "acme"])
        |> Map.put(:query_string, "")
        |> AutoRouteByDevice.call([])

      assert redirected_to(conn) == "/m/acme"
      assert conn.halted
    end

    test "redirects mobile UA from desktop invitation landing to mobile", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", @mobile_ua)
        |> Map.put(:request_path, "/invitations/sometoken")
        |> Map.put(:path_info, ["invitations", "sometoken"])
        |> Map.put(:query_string, "")
        |> AutoRouteByDevice.call([])

      assert redirected_to(conn) == "/m/invitations/sometoken"
      assert conn.halted
    end

    test "redirects desktop UA from mobile invitation landing to desktop", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X)")
        |> Map.put(:request_path, "/m/invitations/sometoken")
        |> Map.put(:path_info, ["m", "invitations", "sometoken"])
        |> Map.put(:query_string, "")
        |> AutoRouteByDevice.call([])

      assert redirected_to(conn) == "/invitations/sometoken"
      assert conn.halted
    end

    test "redirects malformed /entities/m/:slug paths to /m/:slug", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X)")
        |> Map.put(:request_path, "/entities/m/acme")
        |> Map.put(:path_info, ["entities", "m", "acme"])
        |> Map.put(:query_string, "")
        |> AutoRouteByDevice.call([])

      assert redirected_to(conn) == "/m/acme"
      assert conn.halted
    end

    test "redirects mobile UA from desktop invite session to mobile", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", @mobile_ua)
        |> Map.put(:request_path, "/entities/acme/invite-session/member")
        |> Map.put(:path_info, ["entities", "acme", "invite-session", "member"])
        |> Map.put(:query_string, "")
        |> AutoRouteByDevice.call([])

      assert redirected_to(conn) == "/m/acme/invite-session/member"
      assert conn.halted
    end

    test "does not redirect POST requests", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", @mobile_ua)
        |> Map.put(:method, "POST")
        |> Map.put(:request_path, "/invitations/sometoken/accept")
        |> Map.put(:path_info, ["invitations", "sometoken", "accept"])
        |> Map.put(:query_string, "")
        |> AutoRouteByDevice.call([])

      refute conn.halted
    end
  end

  describe "legacy /m/users auth paths via router" do
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
end
