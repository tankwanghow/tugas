defmodule ArgusWeb.TodoLive.TeamLog do
  use ArgusWeb, :live_view

  alias Argus.Todos

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="todo-team-log-page">
        <.header>
          Todo team log
          <:subtitle>Recent todo actions across the team.</:subtitle>
          <:actions>
            <.link
              navigate={~p"/entities/#{@current_scope.entity.slug}/todos"}
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-arrow-left-mini" class="size-4" /> Back to todos
            </.link>
          </:actions>
        </.header>

        <.todo_team_activity logs={@activity} id="todo-team-log" variant={:desktop} />
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load_activity(socket)}
  end

  @impl true
  def handle_event("close_modal_on_escape", _params, socket) do
    {:noreply, socket}
  end

  defp load_activity(socket) do
    scope = socket.assigns.current_scope

    case Todos.list_entity_audit_logs(scope) do
      {:ok, activity} ->
        assign(socket, :activity, activity)

      :not_authorise ->
        assign(socket, :activity, [])
    end
  end
end
