defmodule ArgusWeb.Plugs.AutoRouteByDevice do
  @moduledoc """
  Routes the user to the device-appropriate UI on first visit:

    * `/entities/<slug>/...` (desktop) → `/m/<slug>/...` for mobile UAs
    * `/m/<slug>/...` (mobile)          → `/entities/<slug>/...` for desktop UAs
    * `/invitations/<token>`            ↔ `/m/invitations/<token>`
    * `/m/users/...` (legacy)           → `/users/...` (unified auth UI)

  An `argus_view=mobile|desktop` cookie short-circuits the UA check so
  the user's explicit choice (via the Mobile / Desktop toggle links)
  is respected on every subsequent request.

  Only redirects when the destination route is known to exist on the
  other side. Pages that exist on only one UI (members, etc.)
  pass through untouched so we never 404 the user out.

  Auth (register/log-in) uses a single standalone UI at `/users/...` for
  all devices — no desktop/mobile auth swap.
  """
  @behaviour Plug
  import Plug.Conn

  @mobile_capable_tails [
    "",
    "/obligations/new",
    "/obligation-types",
    "/todos",
    "/todos/new",
    "/members"
  ]

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.method != "GET" do
      conn
    else
      do_route(fetch_cookies(conn))
    end
  end

  defp do_route(conn) do
    cookie = conn.cookies["argus_view"]
    path = conn.request_path

    cond do
      malformed_mobile_entity_path?(path) ->
        redirect_swap(conn, path, "/entities/m/", "/m/")

      legacy_mobile_auth_path?(path) ->
        redirect_swap(conn, path, "/m/users/", "/users/")

      cookie == "mobile" and desktop_url?(path) ->
        maybe_redirect_to_mobile(conn, path)

      cookie == "mobile" and invitation_landing?(path) ->
        redirect_swap(conn, path, "/invitations/", "/m/invitations/")

      cookie == "desktop" and mobile_invitation_landing?(path) ->
        redirect_swap(conn, path, "/m/invitations/", "/invitations/")

      cookie == "desktop" and mobile_url?(path) ->
        redirect_swap(conn, path, "/m/", "/entities/")

      cookie ->
        conn

      mobile_ua?(conn) and desktop_url?(path) ->
        maybe_redirect_to_mobile(conn, path)

      mobile_ua?(conn) and invitation_landing?(path) ->
        redirect_swap(conn, path, "/invitations/", "/m/invitations/")

      not mobile_ua?(conn) and mobile_invitation_landing?(path) ->
        redirect_swap(conn, path, "/m/invitations/", "/invitations/")

      not mobile_ua?(conn) and mobile_url?(path) ->
        redirect_swap(conn, path, "/m/", "/entities/")

      true ->
        conn
    end
  end

  @doc "Tails after `/entities/<slug>` that have a mobile counterpart."
  def mobile_capable_tails, do: @mobile_capable_tails

  defp desktop_url?(path), do: String.starts_with?(path, "/entities/")
  defp mobile_url?(path), do: String.starts_with?(path, "/m/")

  defp malformed_mobile_entity_path?(path), do: String.starts_with?(path, "/entities/m/")

  defp invitation_landing?(path) do
    case String.split(path, "/invitations/", parts: 2) do
      ["", token] -> token != "" and not String.contains?(token, "/")
      _ -> false
    end
  end

  defp mobile_invitation_landing?(path) do
    case String.split(path, "/m/invitations/", parts: 2) do
      ["", token] -> token != "" and not String.contains?(token, "/")
      _ -> false
    end
  end

  defp legacy_mobile_auth_path?(path) do
    path in ["/m/users/register", "/m/users/log-in"] or
      String.match?(path, ~r{^/m/users/log-in/[^/]+$})
  end

  defp mobile_ua?(conn), do: ArgusWeb.Device.mobile_ua?(conn)

  defp maybe_redirect_to_mobile(conn, path) do
    case path_tail(path, "/entities/") do
      {:ok, _slug, tail} ->
        if tail in @mobile_capable_tails or obligation_show?(tail) or invite_session?(tail) do
          redirect_swap(conn, path, "/entities/", "/m/")
        else
          conn
        end

      :error ->
        conn
    end
  end

  defp redirect_swap(conn, path, from, to) do
    new_path = String.replace_prefix(path, from, to)
    qs = if conn.query_string == "", do: "", else: "?" <> conn.query_string

    conn
    |> Phoenix.Controller.redirect(to: new_path <> qs)
    |> halt()
  end

  defp path_tail(path, prefix) do
    case String.split(path, prefix, parts: 2) do
      ["", rest] ->
        case String.split(rest, "/", parts: 2) do
          [slug] -> {:ok, slug, ""}
          [slug, rest_tail] -> {:ok, slug, "/" <> rest_tail}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp obligation_show?(tail), do: String.match?(tail, ~r{^/obligations/[0-9a-f-]+$})

  defp invite_session?(tail),
    do: String.match?(tail, ~r{^/invite-session/(manager|member)$})
end
