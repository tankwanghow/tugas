defmodule ArgusWeb.MobileLive.Dashboard do
  use ArgusWeb, :live_view

  alias ArgusWeb.DashboardFilter
  alias ArgusWeb.ObligationLive.IndexHelpers, as: Index
  import ArgusWeb.MobileLive.Components

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} active={:home}>
      <div class="sticky top-0 z-30 px-4 py-3 bg-base-100/95 backdrop-blur border-b border-base-200 space-y-2">
        <h1 class="text-lg font-semibold truncate">{@current_scope.entity.name}</h1>
        <div class="flex">
          <div class="w-[65%]">
          <input
            id="m-obligation-search"
            type="search"
            name="q"
            placeholder="Search title, type, assignee…"
            phx-keyup="search"
            phx-debounce="150"
            value={@query}
            class="input w-full"
          />
          </div>
          <div class="w-[35%]">
          <form id="m-obligation-status-filter" phx-change="set_status">
            <select name="lifecycle" class="select">
              <option
                :for={{value, label} <- Index.lifecycles()}
                value={value}
                selected={@lifecycle == Index.parse_lifecycle(value)}
              >
                {label}
              </option>
            </select>
          </form>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <div id="m-obligation-scope-toggle" class="tabs tabs-box flex-1">
            <button
              id="m-scope-mine"
              type="button"
              phx-click="set_scope"
              phx-value-mine="true"
              class={["tab flex-1", @mine? && "tab-active"]}
            >
              Mine
            </button>
            <button
              id="m-scope-team"
              type="button"
              phx-click="set_scope"
              phx-value-mine="false"
              class={["tab flex-1", !@mine? && "tab-active"]}
            >
              Team
            </button>
          </div>
          <form id="m-obligation-sort-filter" phx-change="set_sort">
            <select id="m-obligation-sort" name="sort" class="select">
              <option
                :for={{value, label} <- Index.sorts(@lifecycle)}
                value={value}
                selected={@sort == Index.parse_sort(value)}
              >
                {label}
              </option>
            </select>
          </form>
        </div>
      </div>

      <ul
        id="mobile-obligations"
        class="px-4 space-y-2"
        phx-update="stream"
        phx-viewport-bottom={!@end? && "load_more"}
      >
        <.obligation_card
          :for={{dom_id, row} <- @streams.rows}
          id={dom_id}
          row={row}
          today={@today}
          slug={@current_scope.entity.slug}
        />
      </ul>
      <div
        :if={@empty?}
        id="m-obligations-empty"
        class="text-center text-base-content/60 py-12"
      >
        {Index.empty_message(@mine?, @lifecycle)}
      </div>
    </Layouts.mobile_app>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    scope = socket.assigns.current_scope
    today = Argus.Obligations.Urgency.today_for(scope.entity.timezone)

    {:ok,
     socket
     |> assign(:today, today)
     |> DashboardFilter.assign_filters(session)
     |> load_first_page()}
  end

  @impl true
  def handle_event("set_scope", %{"mine" => mine}, socket) do
    {:noreply,
     socket |> assign(:mine?, mine == "true") |> load_first_page() |> DashboardFilter.persist()}
  end

  def handle_event("set_status", %{"lifecycle" => lifecycle}, socket) do
    {:noreply,
     socket
     |> assign(:lifecycle, Index.parse_lifecycle(lifecycle))
     |> load_first_page()
     |> DashboardFilter.persist()}
  end

  def handle_event("set_sort", %{"sort" => sort}, socket) do
    {:noreply,
     socket
     |> assign(:sort, Index.parse_sort(sort))
     |> load_first_page()
     |> DashboardFilter.persist()}
  end

  def handle_event("search", params, socket) do
    query = Map.get(params, "value") || Map.get(params, "q") || ""

    {:noreply, socket |> assign(:query, query) |> load_first_page() |> DashboardFilter.persist()}
  end

  def handle_event("load_more", _params, socket) do
    %{
      current_scope: scope,
      today: today,
      mine?: mine?,
      lifecycle: lifecycle,
      query: query,
      sort: sort,
      cursor: cursor
    } = socket.assigns

    %{rows: rows, cursor: cursor, end?: end?} =
      Index.load_page(scope, today, mine?, lifecycle, query, sort, cursor)

    {:noreply,
     socket
     |> stream(:rows, rows, dom_id: &row_dom_id/1, at: -1)
     |> assign(cursor: cursor, end?: end?)}
  end

  def handle_event("close_modal_on_escape", _params, socket), do: {:noreply, socket}

  defp load_first_page(socket) do
    %{
      current_scope: scope,
      today: today,
      mine?: mine?,
      lifecycle: lifecycle,
      query: query,
      sort: sort
    } = socket.assigns

    %{rows: rows, cursor: cursor, end?: end?} =
      Index.load_page(scope, today, mine?, lifecycle, query, sort, nil)

    socket
    |> stream(:rows, rows, dom_id: &row_dom_id/1, reset: true)
    |> assign(cursor: cursor, end?: end?, empty?: rows == [])
  end

  defp row_dom_id(row), do: "m-ob-#{row.obligation.id}"
end
