defmodule ArgusWeb.MobileLive.TodoTeamLog do
  use ArgusWeb, :live_view

  alias Argus.Todos

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} active={:more}>
      <div id="m-todo-team-log-page" class="p-4">
        <div class="flex items-center justify-between gap-2 mb-3">
          <div class="font-semibold text-xl">Todo team log</div>
          <.link
            navigate={~p"/m/#{@current_scope.entity.slug}/todos"}
            class="btn btn-ghost btn-xs"
          >
            Todos
          </.link>
        </div>
        <p class="text-xs text-base-content/60 mb-3">
          Recent todo actions across the team.
        </p>

        <.todo_team_activity logs={@activity} id="m-todo-team-log" variant={:mobile} />
      </div>
    </Layouts.mobile_app>
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
