defmodule ArgusWeb.MobileLive.TodoTeamLog do
  use ArgusWeb, :live_view

  alias ArgusWeb.TodoLive.TeamLogHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} active={:more}>
      <div id="m-todo-team-log-page" class="p-4">
        <div class="flex items-center justify-between gap-2 mb-3">
          <div class="font-semibold text-xl">Todo team log</div>
        </div>
        <p class="text-xs text-base-content/60 mb-3">
          Recent todo actions across the team.
        </p>

        <form
          id="m-todo-team-log-filter"
          phx-change="filter"
          phx-submit="filter"
          class="mb-3 flex space-y-2"
        >
          <input
            type="text"
            name="search"
            value={@filter_search}
            placeholder="Search by todo or person…"
            phx-debounce="300"
            class="input input-bordered w-[70%]"
          />
          <select name="action" class="select select-bordered w-[30%]">
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
          id="m-todo-team-log"
          rows={@streams.activity}
          empty?={@empty?}
          end?={@end?}
          entity_slug={@current_scope.entity.slug}
          variant={:mobile}
        />
      </div>
    </Layouts.mobile_app>
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
