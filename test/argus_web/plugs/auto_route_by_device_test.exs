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

      refute "/obligations/new" in tails
      refute "/obligation-types" in tails
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

    test "redirects mobile UA from desktop obligations list to mobile", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", @mobile_ua)
        |> Map.put(:request_path, "/entities/acme/obligations")
        |> Map.put(:path_info, ["entities", "acme", "obligations"])
        |> Map.put(:query_string, "")
        |> AutoRouteByDevice.call([])

      assert redirected_to(conn) == "/m/acme/obligations"
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

    test "does not redirect mobile UA on desktop-only obligation create", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", @mobile_ua)
        |> Map.put(:request_path, "/entities/acme/obligations/new")
        |> Map.put(:path_info, ["entities", "acme", "obligations", "new"])
        |> Map.put(:query_string, "")
        |> AutoRouteByDevice.call([])

      refute conn.halted
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

    test "redirects mobile UA from desktop entity picker to mobile picker", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", @mobile_ua)
        |> Map.put(:request_path, "/entities")
        |> Map.put(:path_info, ["entities"])
        |> Map.put(:query_string, "pick=1")
        |> AutoRouteByDevice.call([])

      assert redirected_to(conn) == "/m/entities?pick=1"
      assert conn.halted
    end

    test "redirects desktop UA from mobile entity picker to desktop picker", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X)")
        |> Map.put(:request_path, "/m/entities")
        |> Map.put(:path_info, ["m", "entities"])
        |> Map.put(:query_string, "pick=1")
        |> AutoRouteByDevice.call([])

      assert redirected_to(conn) == "/entities?pick=1"
      assert conn.halted
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
  end
end
