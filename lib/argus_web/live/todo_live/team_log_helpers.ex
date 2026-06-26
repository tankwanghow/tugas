defmodule ArgusWeb.TodoLive.TeamLogHelpers do
  @moduledoc """
  Shared (Desktop + Mobile) non-render logic for the todo team log: the action dropdown +
  single actor/title search (pushed into SQL) and keyset-paged infinite scroll over
  `Argus.Todos.list_entity_audit_logs_page/2`, rendered as a LiveView stream.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 4]

  alias Argus.Todos
  alias ArgusWeb.TodoLive.ActivityFormat

  def mount_assigns(socket) do
    socket
    |> assign(:filter_action, "")
    |> assign(:filter_search, "")
    |> assign(:cursor, nil)
    |> load_first_page()
  end

  def handle_filter(socket, params) do
    socket
    |> assign(:filter_action, params["action"] || "")
    |> assign(:filter_search, params["search"] || "")
    |> load_first_page()
  end

  def handle_load_more(socket) do
    if socket.assigns.end? do
      socket
    else
      case page(socket, socket.assigns.cursor) do
        {:ok, %{rows: rows, cursor: cursor, end?: end?}} ->
          socket
          |> stream(:activity, rows, at: -1)
          |> assign(:cursor, cursor)
          |> assign(:end?, end?)

        :not_authorise ->
          socket
      end
    end
  end

  @doc "Flash shown when a log entry's todo has since been deleted (no board row to open)."
  def deleted_notice, do: "That todo was deleted — it's no longer on the board."

  @doc "Options for the action filter `<select>`: `[{label, value}, ...]`."
  def action_options do
    [{"All actions", ""}] ++
      Enum.map(Todos.audit_actions(), &{ActivityFormat.audit_action_label(&1), &1})
  end

  defp load_first_page(socket) do
    case page(socket, nil) do
      {:ok, %{rows: rows, cursor: cursor, end?: end?}} ->
        socket
        |> stream(:activity, rows, reset: true)
        |> assign(:cursor, cursor)
        |> assign(:end?, end?)
        |> assign(:empty?, rows == [])

      :not_authorise ->
        socket
        |> stream(:activity, [], reset: true)
        |> assign(:cursor, nil)
        |> assign(:end?, true)
        |> assign(:empty?, true)
    end
  end

  defp page(socket, cursor) do
    Todos.list_entity_audit_logs_page(socket.assigns.current_scope,
      action: socket.assigns.filter_action,
      search: socket.assigns.filter_search,
      cursor: cursor
    )
  end
end
