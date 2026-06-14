defmodule ArgusWeb.Plugs.AutoRouteByDevice do
  @moduledoc """
  Routes the user to the device-appropriate UI:

    * `/entities/<slug>/...` (desktop) → `/m/<slug>/...` for mobile UAs
    * `/m/<slug>/...` (mobile)          → `/entities/<slug>/...` for desktop UAs

  An `argus_view=mobile|desktop` cookie overrides UA detection.

  Only redirects when the destination route exists on the other side
  (field-work surface: dashboard, obligations list, obligation show).
  """
  @behaviour Plug
  import Plug.Conn

  @mobile_capable_tails ["", "/obligations"]

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)
    cookie = conn.cookies["argus_view"]
    path = conn.request_path

    cond do
      cookie == "mobile" and path == "/entities" ->
        redirect_picker(conn, "/entities", "/m/entities")

      cookie == "desktop" and path == "/m/entities" ->
        redirect_picker(conn, "/m/entities", "/entities")

      cookie == "mobile" and desktop_url?(path) ->
        maybe_redirect_to_mobile(conn, path)

      cookie == "desktop" and mobile_url?(path) ->
        redirect_swap(conn, path, "/m/", "/entities/")

      cookie ->
        conn

      mobile_ua?(conn) and path == "/entities" ->
        redirect_picker(conn, "/entities", "/m/entities")

      not mobile_ua?(conn) and path == "/m/entities" ->
        redirect_picker(conn, "/m/entities", "/entities")

      mobile_ua?(conn) and desktop_url?(path) ->
        maybe_redirect_to_mobile(conn, path)

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

  defp mobile_ua?(conn), do: ArgusWeb.Device.mobile_ua?(conn)

  defp maybe_redirect_to_mobile(conn, path) do
    case path_tail(path, "/entities/") do
      {:ok, _slug, tail} ->
        if tail in @mobile_capable_tails or obligation_show?(tail) do
          redirect_swap(conn, path, "/entities/", "/m/")
        else
          conn
        end

      :error ->
        conn
    end
  end

  defp redirect_picker(conn, _from, to) do
    qs = if conn.query_string == "", do: "", else: "?" <> conn.query_string

    conn
    |> Phoenix.Controller.redirect(to: to <> qs)
    |> halt()
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
end
