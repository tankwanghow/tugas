defmodule ArgusWeb.TodoLive.TeamLog do
  use ArgusWeb, :live_view

  alias ArgusWeb.TodoLive.TeamLogHelpers

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

        <form
          id="todo-team-log-filter"
          phx-change="filter"
          phx-submit="filter"
          class="mt-2 flex flex-wrap items-center gap-2"
        >
          <input
            type="text"
            name="search"
            value={@filter_search}
            placeholder="Search by todo or person…"
            phx-debounce="300"
            class="input input-bordered w-full sm:w-72"
          />
          <select name="action" class="select select-bordered">
            <option
              :for={{label, value} <- TeamLogHelpers.action_options()}
              value={value}
              selected={value == @filter_action}
            >
              {label}
            </option>
          </select>
        </form>

        <.todo_team_activity
          id="todo-team-log"
          rows={@streams.activity}
          empty?={@empty?}
          end?={@end?}
          entity_slug={@current_scope.entity.slug}
          variant={:desktop}
        />
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, TeamLogHelpers.mount_assigns(socket)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply, TeamLogHelpers.handle_filter(socket, params)}
  end

  def handle_event("load_more", _params, socket) do
    {:noreply, TeamLogHelpers.handle_load_more(socket)}
  end

  def handle_event("deleted_todo_notice", _params, socket) do
    {:noreply, put_flash(socket, :info, TeamLogHelpers.deleted_notice())}
  end

  def handle_event("close_modal_on_escape", _params, socket) do
    {:noreply, socket}
  end
end
