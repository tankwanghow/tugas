defmodule ArgusWeb.LegacyAuthRedirectController do
  @moduledoc """
  Redirects legacy `/m/users/*` bookmark URLs to the unified `/users/*` auth routes.
  """
  use ArgusWeb, :controller

  def show(conn, %{"token" => token}) do
    redirect(conn, to: ~p"/users/log-in/#{token}")
  end

  def show(conn, _params) do
    to =
      conn.request_path
      |> String.replace_prefix("/m/users", "/users")

    redirect(conn, to: to)
  end
end
