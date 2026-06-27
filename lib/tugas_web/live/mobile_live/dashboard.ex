defmodule TugasWeb.MobileLive.Dashboard do
  use TugasWeb, :live_view

  alias TugasWeb.DashboardLive.CalendarHelpers, as: Calendar
  alias TugasWeb.DashboardLive.IndexHelpers, as: Dashboard

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} nav_context={:calendar}>
      <div class="sticky top-0 z-30 px-4 py-3 bg-base-100/95 backdrop-blur border-b border-base-200 space-y-2">
        <h1 class="flex items-center gap-2 text-lg font-semibold truncate">
          <.brand_logo class="size-9" /> Calendar -
          <span class="text-base-content/50">{@current_scope.entity.slug}</span>
        </h1>
        <div id="dashboard-scope-toggle" class="tabs tabs-box">
          <button
            id="dashboard-scope-mine"
            type="button"
            phx-click="set_scope"
            phx-value-mine="true"
            class={["tab flex-1", @mine? && "tab-active font-bold"]}
          >
            Mine
          </button>
          <button
            id="dashboard-scope-team"
            type="button"
            phx-click="set_scope"
            phx-value-mine="false"
            class={["tab flex-1", !@mine? && "tab-active font-bold"]}
          >
            Team
          </button>
        </div>
        <div class="flex items-center gap-1">
          <button
            id="dashboard-prev-month"
            type="button"
            class="btn btn-outline btn-sm font-bold"
            phx-click="prev_month"
          >
            ‹
          </button>
          <span id="dashboard-month-label" class="text-sm font-semibold flex-1 text-center">
            {Calendar.month_label(@year, @month)}
          </span>
          <button
            id="dashboard-next-month"
            type="button"
            class="btn btn-outline btn-sm font-bold"
            phx-click="next_month"
          >
            ›
          </button>
          <button
            id="dashboard-today"
            type="button"
            class="btn btn-outline btn-sm"
            phx-click="today"
          >
            Today
          </button>
        </div>
      </div>

      <div id="m-dashboard" phx-hook="DashboardSwipe" class="px-4 py-3 space-y-2">
        <div
          id="m-dashboard-swipe-hint"
          class="flex items-center justify-between px-1"
        >
          <button
            type="button"
            id="m-dashboard-go-someday"
            data-dashboard-go="0"
            class="min-h-10 px-2 py-2 text-sm text-base-content/50 rounded-lg active:bg-base-200"
          >
            ← Someday
          </button>
          <div id="m-dashboard-dots" class="flex items-center gap-1.5" aria-hidden="true">
            <span data-dashboard-panel="0" class="size-1.5 rounded-full bg-base-content/20" />
            <span data-dashboard-panel="1" class="size-1.5 rounded-full bg-primary" />
            <span data-dashboard-panel="2" class="size-1.5 rounded-full bg-base-content/20" />
          </div>
          <button
            type="button"
            id="m-dashboard-go-todos"
            data-dashboard-go="2"
            class="min-h-10 px-2 py-2 text-sm text-base-content/50 rounded-lg active:bg-base-200"
          >
            Todos →
          </button>
        </div>

        <div
          id="m-dashboard-swipe"
          class="flex h-[calc(100dvh-15.5rem)] snap-x snap-mandatory overflow-x-auto overflow-y-hidden scroll-smooth [scrollbar-width:none] [-ms-overflow-style:none] [&::-webkit-scrollbar]:hidden"
        >
          <div class="w-full shrink-0 snap-center h-full min-h-0 overflow-y-auto pr-2">
            <.mobile_someday_panel
              rows={@someday_rows}
              slug={@current_scope.entity.slug}
              variant={:mobile}
            />
          </div>

          <div class="w-full shrink-0 snap-center h-full min-h-0 overflow-y-auto px-1">
            <.duty_calendar
              variant={:mobile}
              hide_someday_strip?={true}
              grid={@grid}
              grouped={@grouped}
              someday_rows={@someday_rows}
              slug={@current_scope.entity.slug}
              day_modal_date={@day_modal_date}
              day_modal_rows={@day_modal_rows}
              someday_modal_open?={@someday_modal_open?}
            />
          </div>

          <div class="w-full shrink-0 snap-center h-full min-h-0 overflow-y-auto pl-2">
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
