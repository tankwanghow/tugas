defmodule TugasWeb.DashboardLive.Index do
  use TugasWeb, :live_view

  alias Tugas.Authorization
  alias TugasWeb.DashboardLive.CalendarHelpers, as: Calendar
  alias TugasWeb.DashboardLive.IndexHelpers, as: Dashboard
  alias TugasWeb.DutyLive.FormComponent

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      container_class="max-w-7xl"
      full_height
    >
      <div id="dashboard" class="flex h-full min-h-0 flex-col gap-3">
        <div class="flex shrink-0 flex-wrap items-center justify-center gap-2">
          <div class="flex items-center gap-1">
            <button
              id="dashboard-prev-month"
              type="button"
              class="btn btn-outline text-3xl font-bold"
              phx-click="prev_month"
            >
              ‹
            </button>
            <span id="dashboard-month-label" class="text-2xl font-semibold min-w-32 text-center">
              {Calendar.month_label(@year, @month)}
            </span>
            <button
              id="dashboard-next-month"
              type="button"
              class="btn btn-outline text-3xl font-bold"
              phx-click="next_month"
            >
              ›
            </button>
            <button
              id="dashboard-today"
              type="button"
              class="btn btn-outline"
              phx-click="today"
            >
              Today
            </button>
            <button
              :if={Authorization.can?(@current_scope, :create_duty)}
              id="dashboard-new-duty"
              type="button"
              class="btn btn-primary"
              phx-click="open_create_duty"
            >
              + Duty
            </button>
            <button
              id="dashboard-new-todo"
              type="button"
              class="btn btn-secondary"
              phx-click="open_new_todo"
            >
              + Todo
            </button>
          </div>
        </div>

        <div class={grid_cols_class(@collapsed)}>
          <.urgent_panel
            rows={@urgent_rows}
            slug={@current_scope.entity.slug}
            collapsed?={@collapsed.urgent}
          />

          <div class="flex h-full min-h-0 min-w-0 flex-col">
            <.duty_calendar
              grid={@grid}
              grouped={@grouped}
              someday_rows={@someday_rows}
              slug={@current_scope.entity.slug}
              day_modal_date={@day_modal_date}
              day_modal_rows={@day_modal_rows}
              day_modal_holidays={@day_modal_holidays}
              someday_collapsed?={@collapsed.someday}
            />
          </div>

          <.dashboard_todos_panel
            todos={@todos}
            completed_todos={@completed_todos}
            slug={@current_scope.entity.slug}
            row_effects={@row_effects}
            collapsed?={@collapsed.todos}
          />
        </div>

        <.live_component
          :if={@create_duty_open?}
          module={FormComponent}
          id="duty-form-modal"
          current_scope={@current_scope}
          from_todo_id={@create_duty_from_todo_id}
        />

        <.new_todo_modal :if={@new_todo_open?} />
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, session, socket), do: Dashboard.mount_dashboard(socket, session)

  @impl true
  def handle_params(params, _uri, socket) do
    if socket.assigns.live_action == :new and
         Authorization.can?(socket.assigns.current_scope, :create_duty) do
      {:noreply, Dashboard.handle_open_create_duty(socket, params)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("prev_month", _params, socket) do
    {:noreply, Dashboard.handle_prev_month(socket)}
  end

  def handle_event("next_month", _params, socket) do
    {:noreply, Dashboard.handle_next_month(socket)}
  end

  def handle_event("today", _params, socket) do
    {:noreply, Dashboard.handle_today(socket)}
  end

  def handle_event("open_day_modal", %{"date" => iso}, socket) do
    {:noreply, Dashboard.handle_open_day_modal(socket, iso)}
  end

  def handle_event("close_day_modal", _params, socket) do
    {:noreply, Dashboard.handle_close_day_modal(socket)}
  end

  def handle_event("toggle_panel", %{"panel" => panel}, socket) do
    {:noreply, Dashboard.handle_toggle_panel(socket, panel)}
  end

  def handle_event("open_create_duty", _params, socket) do
    {:noreply, Dashboard.handle_open_create_duty(socket)}
  end

  def handle_event("close_create_duty", _params, socket) do
    {:noreply, Dashboard.handle_close_create_duty(socket)}
  end

  def handle_event("open_new_todo", _params, socket) do
    {:noreply, Dashboard.handle_open_new_todo(socket)}
  end

  def handle_event("close_new_todo", _params, socket) do
    {:noreply, Dashboard.handle_close_new_todo(socket)}
  end

  def handle_event("create_todo", %{"title" => title}, socket) do
    {:noreply, Dashboard.handle_create_todo(socket, title)}
  end

  def handle_event("toggle_todo_complete", %{"id" => id}, socket) do
    {:noreply, Dashboard.handle_toggle_todo_complete(socket, id)}
  end

  def handle_event("finish_row_effect", %{"id" => id}, socket) do
    {:noreply, Dashboard.handle_finish_row_effect(socket, id)}
  end

  def handle_event("close_modal_on_escape", _params, socket) do
    {:noreply, Dashboard.handle_close_modal_on_escape(socket)}
  end

  @impl true
  def handle_info({:duty_created, duty, from_todo_id}, socket) do
    {:noreply, Dashboard.handle_duty_created(socket, duty, from_todo_id)}
  end

  # Collapsing Urgent (left) / Todos (right) shrinks that column to a thin rail so
  # the calendar (the 1fr middle column) expands to take the freed width. The grid
  # is flex-1/min-h-0 so the whole dashboard fills the viewport and only the inner
  # lists scroll (the page itself never scrolls).
  @grid_base "grid min-h-0 flex-1 grid-cols-1 gap-2"

  defp grid_cols_class(%{urgent: true, todos: true}),
    do: "#{@grid_base} lg:grid-cols-[2.5rem_minmax(0,1fr)_2.5rem]"

  defp grid_cols_class(%{urgent: true}),
    do: "#{@grid_base} lg:grid-cols-[2.5rem_minmax(0,1fr)_15%]"

  defp grid_cols_class(%{todos: true}),
    do: "#{@grid_base} lg:grid-cols-[15%_minmax(0,1fr)_2.5rem]"

  defp grid_cols_class(_),
    do: "#{@grid_base} lg:grid-cols-[15%_minmax(0,1fr)_15%]"
end
