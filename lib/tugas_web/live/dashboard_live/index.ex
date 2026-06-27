defmodule TugasWeb.DashboardLive.Index do
  use TugasWeb, :live_view

  alias Tugas.Duties.Urgency
  alias Tugas.Todos
  alias Tugas.Todos.Todo
  alias TugasWeb.DashboardLive.CalendarHelpers, as: Calendar
  alias TugasWeb.DutiesFilter
  @open_preview_limit 10
  @completed_preview_limit 10

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} container_class="max-w-7xl">
      <div id="dashboard" class="tugas-page space-y-4">
        <div class="flex flex-wrap items-center gap-2">
          <div id="dashboard-scope-toggle" class="tabs tabs-box">
            <button
              id="dashboard-scope-mine"
              type="button"
              phx-click="set_scope"
              phx-value-mine="true"
              class={["tab", @mine? && "tab-active font-bold"]}
            >
              Mine
            </button>
            <button
              id="dashboard-scope-team"
              type="button"
              phx-click="set_scope"
              phx-value-mine="false"
              class={["tab", !@mine? && "tab-active font-bold"]}
            >
              Team
            </button>
          </div>

          <div class="flex items-center gap-1 ml-auto">
            <button
              id="dashboard-prev-month"
              type="button"
              class="btn btn-ghost btn-sm"
              phx-click="prev_month"
            >
              ‹
            </button>
            <span id="dashboard-month-label" class="text-sm font-semibold min-w-32 text-center">
              {Calendar.month_label(@year, @month)}
            </span>
            <button
              id="dashboard-next-month"
              type="button"
              class="btn btn-ghost btn-sm"
              phx-click="next_month"
            >
              ›
            </button>
            <button
              id="dashboard-today"
              type="button"
              class="btn btn-ghost btn-sm"
              phx-click="today"
            >
              Today
            </button>
          </div>
        </div>

        <div class="flex flex-col lg:flex-row gap-6 lg:items-stretch min-h-0">
          <div class="flex-1 min-w-0 min-h-0">
            <.duty_calendar
              grid={@grid}
              grouped={@grouped}
              someday_rows={@someday_rows}
              slug={@current_scope.entity.slug}
              day_modal_date={@day_modal_date}
              day_modal_rows={@day_modal_rows}
              someday_modal_open?={@someday_modal_open?}
            />
          </div>

          <div class="w-full lg:w-[15%] shrink-0 flex flex-col min-h-0 lg:h-auto lg:self-stretch">
            <.dashboard_todos_panel
              todos={@todos}
              completed_todos={@completed_todos}
              slug={@current_scope.entity.slug}
              row_effects={@row_effects}
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    scope = socket.assigns.current_scope
    today = Urgency.today_for(scope.entity.timezone)
    {year, month} = Calendar.current_month(today)

    socket =
      socket
      |> assign(:today, today)
      |> assign(:year, year)
      |> assign(:month, month)
      |> assign(:day_modal_date, nil)
      |> assign(:day_modal_rows, [])
      |> assign(:someday_modal_open?, false)
      |> assign(:row_effects, %{})
      |> DutiesFilter.assign_filters(session)
      |> load_dashboard()

    {:ok, socket}
  end

  @impl true
  def handle_event("set_scope", %{"mine" => mine}, socket) do
    {:noreply,
     socket
     |> assign(:mine?, mine == "true")
     |> load_dashboard()
     |> DutiesFilter.persist()}
  end

  def handle_event("prev_month", _params, socket) do
    {year, month} = Calendar.shift_month(socket.assigns.year, socket.assigns.month, -1)

    {:noreply,
     socket
     |> assign(year: year, month: month)
     |> load_dashboard()}
  end

  def handle_event("next_month", _params, socket) do
    {year, month} = Calendar.shift_month(socket.assigns.year, socket.assigns.month, 1)

    {:noreply,
     socket
     |> assign(year: year, month: month)
     |> load_dashboard()}
  end

  def handle_event("today", _params, socket) do
    today = socket.assigns.today
    {year, month} = Calendar.current_month(today)

    {:noreply,
     socket
     |> assign(year: year, month: month)
     |> load_dashboard()}
  end

  def handle_event("open_day_modal", %{"date" => iso}, socket) do
    date = Date.from_iso8601!(iso)
    rows = Map.get(socket.assigns.grouped, date, [])

    {:noreply,
     socket
     |> assign(day_modal_date: date, day_modal_rows: rows)
     |> assign(:someday_modal_open?, false)}
  end

  def handle_event("close_day_modal", _params, socket) do
    {:noreply, assign(socket, day_modal_date: nil, day_modal_rows: [])}
  end

  def handle_event("open_someday_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:someday_modal_open?, true)
     |> assign(day_modal_date: nil, day_modal_rows: [])}
  end

  def handle_event("close_someday_modal", _params, socket) do
    {:noreply, assign(socket, :someday_modal_open?, false)}
  end

  def handle_event("toggle_todo_complete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    socket =
      case Todos.get_todo(scope, id) do
        {:ok, todo} ->
          case Todos.toggle_complete(scope, todo) do
            {:ok, updated} ->
              effect = if Todo.completed?(updated), do: :completed, else: :updated

              socket =
                if Todo.completed?(updated) do
                  assign(socket, :todos, replace_todo(socket.assigns.todos, updated))
                else
                  assign(socket, :completed_todos, replace_todo(socket.assigns.completed_todos, updated))
                end

              put_row_effect(socket, updated.id, effect)

            _ ->
              socket
          end

        _ ->
          socket
      end

    {:noreply, socket}
  end

  def handle_event("finish_row_effect", %{"id" => id}, socket) do
    effect = Map.get(socket.assigns.row_effects || %{}, id)
    row_effects = Map.delete(socket.assigns.row_effects || %{}, id)

    {todos, completed_todos} =
      case effect do
        :completed ->
          todo = Enum.find(socket.assigns.todos, &(&1.id == id))

          {
            Enum.reject(socket.assigns.todos, &(&1.id == id)),
            prepend_unique(socket.assigns.completed_todos, todo, @completed_preview_limit)
          }

        :updated ->
          todo = Enum.find(socket.assigns.completed_todos, &(&1.id == id))

          {
            prepend_unique(socket.assigns.todos, todo, @open_preview_limit),
            Enum.reject(socket.assigns.completed_todos, &(&1.id == id))
          }

        _ ->
          {socket.assigns.todos, socket.assigns.completed_todos}
      end

    {:noreply,
     assign(socket, row_effects: row_effects, todos: todos, completed_todos: completed_todos)}
  end

  def handle_event("close_modal_on_escape", _params, socket) do
    cond do
      socket.assigns.day_modal_date ->
        {:noreply, assign(socket, day_modal_date: nil, day_modal_rows: [])}

      socket.assigns.someday_modal_open? ->
        {:noreply, assign(socket, :someday_modal_open?, false)}

      true ->
        {:noreply, socket}
    end
  end

  defp load_dashboard(socket) do
    %{current_scope: scope, today: today, mine?: mine?, year: year, month: month} =
      socket.assigns

    month_rows = Calendar.load_month_rows(scope, today, mine?, year, month)
    someday_rows = Calendar.load_someday_rows(scope, today, mine?)
    grid = Calendar.build_month_grid(year, month, today)
    grouped = Calendar.group_by_date(month_rows)

    socket
    |> assign(grid: grid, grouped: grouped, someday_rows: someday_rows)
    |> load_todos()
  end

  defp load_todos(socket) do
    scope = socket.assigns.current_scope

    todos =
      case Todos.list_todos_page(scope, status: :open, limit: @open_preview_limit) do
        {:ok, %{rows: rows}} -> rows
        _ -> []
      end

    completed_todos =
      case Todos.list_todos_page(scope, status: :completed, limit: @completed_preview_limit) do
        {:ok, %{rows: rows}} -> rows
        _ -> []
      end

    socket
    |> assign(:todos, todos)
    |> assign(:completed_todos, completed_todos)
  end

  defp replace_todo(todos, %Todo{} = updated) do
    case Enum.find_index(todos, &(&1.id == updated.id)) do
      nil -> todos
      idx -> List.replace_at(todos, idx, updated)
    end
  end

  defp put_row_effect(socket, todo_id, effect) do
    assign(socket, :row_effects, Map.put(socket.assigns.row_effects || %{}, todo_id, effect))
  end

  defp prepend_unique(list, nil, _limit), do: list

  defp prepend_unique(list, %Todo{} = todo, limit) do
    [todo | Enum.reject(list, &(&1.id == todo.id))] |> Enum.take(limit)
  end
end
