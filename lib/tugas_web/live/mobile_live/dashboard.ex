defmodule TugasWeb.MobileLive.Dashboard do
  use TugasWeb, :live_view

  alias TugasWeb.DashboardLive.CalendarHelpers, as: Calendar
  alias TugasWeb.DashboardLive.IndexHelpers, as: Dashboard

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} nav_context={:calendar}>
      <div class="flex h-[calc(100dvh-4.5rem-env(safe-area-inset-bottom,0px))] min-h-0 flex-col">
        <div class="sticky top-0 z-30 shrink-0 px-4 pt-3 bg-base-100/95 backdrop-blur space-y-1">
          <div id="dashboard-scope-toggle" class="flex items-center justify-between gap-1">
            <button
              id="dashboard-scope-mine"
              type="button"
              phx-click="set_scope"
              phx-value-mine="true"
              class={["border border-base-300 rounded-lg px-2 py-1", @mine? && "border-2 font-bold"]}
            >
              Mine
            </button>
            <button
              id="dashboard-scope-team"
              type="button"
              phx-click="set_scope"
              phx-value-mine="false"
              class={["border border-base-300 rounded-lg px-2 py-1", !@mine? && "border-2 font-bold"]}
            >
              Team
            </button>
            <button
              id="dashboard-prev-month"
              type="button"
              class="border border-base-300 rounded-lg px-3 py-1 font-bold"
              phx-click="prev_month"
            >
              ‹
            </button>
            <span id="dashboard-month-label" class="font-semibold min-w-20 text-center">
              {Calendar.month_label(@year, @month)}
            </span>
            <button
              id="dashboard-next-month"
              type="button"
              class="border border-base-300 rounded-lg px-3 py-1 font-bold"
              phx-click="next_month"
            >
              ›
            </button>
            <button
              id="dashboard-today"
              type="button"
              class="border border-base-300 rounded-lg px-2 py-1"
              phx-click="today"
            >
              Today
            </button>
          </div>
        </div>

        <div
          id="m-dashboard"
          phx-hook="DashboardSwipe"
          class="flex min-h-0 flex-1 flex-col px-1 py-1 gap-1"
        >
          <div id="m-dashboard-swipe-hint" class="tabs tabs-box w-full shrink-0">
            <button
              type="button"
              id="m-dashboard-go-someday"
              data-dashboard-go="0"
              class="tab flex-1 min-h-8 text-sm"
            >
              someday
            </button>
            <button
              type="button"
              id="m-dashboard-go-calendar"
              data-dashboard-go="1"
              class="tab flex-1 min-h-8 text-sm tab-active font-bold"
            >
              calendar
            </button>
            <button
              type="button"
              id="m-dashboard-go-todos"
              data-dashboard-go="2"
              class="tab flex-1 min-h-8 text-sm"
            >
              todo
            </button>
          </div>

          <div id="m-dashboard-panels" class="relative flex min-h-0 flex-1 flex-col">
            <div
              data-dashboard-panel="0"
              class="hidden min-h-0 flex-1 overflow-y-auto pr-2"
            >
              <.mobile_someday_panel
                rows={@someday_rows}
                slug={@current_scope.entity.slug}
                variant={:mobile}
              />
            </div>

            <div
              data-dashboard-panel="1"
              class="flex min-h-0 flex-1 flex-col overflow-hidden px-1"
            >
              <.duty_calendar
                variant={:mobile}
                hide_someday_strip?={true}
                grid={@grid}
                grouped={@grouped}
                someday_rows={@someday_rows}
                slug={@current_scope.entity.slug}
                day_modal_date={@day_modal_date}
                day_modal_rows={@day_modal_rows}
                day_modal_holidays={@day_modal_holidays}
                someday_modal_open?={@someday_modal_open?}
              />
            </div>

            <div
              data-dashboard-panel="2"
              class="hidden min-h-0 flex-1 overflow-y-auto pl-2"
            >
              <.dashboard_todos_panel
                variant={:mobile}
                todos={@todos}
                completed_todos={@completed_todos}
                slug={@current_scope.entity.slug}
                row_effects={@row_effects}
              />
            </div>
          </div>
        </div>
      </div>
    </Layouts.mobile_app>
    """
  end

  @impl true
  def mount(_params, session, socket), do: Dashboard.mount_dashboard(socket, session)

  @impl true
  def handle_event("set_scope", %{"mine" => mine}, socket) do
    {:noreply, Dashboard.handle_set_scope(socket, mine)}
  end

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

  def handle_event("open_someday_modal", _params, socket) do
    {:noreply, Dashboard.handle_open_someday_modal(socket)}
  end

  def handle_event("close_someday_modal", _params, socket) do
    {:noreply, Dashboard.handle_close_someday_modal(socket)}
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
end
