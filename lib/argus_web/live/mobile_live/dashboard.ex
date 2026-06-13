defmodule ArgusWeb.MobileLive.Dashboard do
  use ArgusWeb, :live_view

  alias Argus.Obligations
  alias Argus.Obligations.Urgency
  import ArgusWeb.MobileLive.Components

  @urgency_rank %{overdue: 0, due_soon: 1, ok: 2}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} active={:home}>
      <div class="sticky top-0 z-30 -mx-4 px-4 py-3 bg-base-100/95 backdrop-blur border-b border-base-200">
        <h1 class="text-lg font-semibold truncate">{@current_scope.entity.name}</h1>
        <div class="mt-2 tabs tabs-box w-full">
          <button
            class={["tab flex-1", @tab == :my_work && "tab-active"]}
            phx-click="tab"
            phx-value-tab="my_work"
          >
            My work
          </button>
          <button
            class={["tab flex-1", @tab == :team && "tab-active"]}
            phx-click="tab"
            phx-value-tab="team"
          >
            Team
          </button>
        </div>
        <input
          type="text"
          name="q"
          placeholder="Search obligations…"
          phx-keyup="search"
          phx-debounce="150"
          value={@query}
          class="input w-full mt-2"
        />
      </div>

      <ul id="mobile-obligations" class="mt-3 space-y-2">
        <.obligation_card
          :for={row <- @rows}
          row={row}
          today={@today}
          slug={@current_scope.entity.slug}
        />
        <li :if={@rows == []} class="text-center text-base-content/60 py-12">
          No live obligations.
        </li>
      </ul>
    </Layouts.mobile_app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    today = Urgency.today_for(scope.entity.timezone)
    tab = if scope.role == :member, do: :my_work, else: :team

    {:ok,
     socket
     |> assign(today: today, tab: tab, query: "")
     |> load_rows()}
  end

  @impl true
  def handle_event("tab", %{"tab" => tab}, socket) do
    tab = if tab == "team", do: :team, else: :my_work
    {:noreply, socket |> assign(:tab, tab) |> load_rows()}
  end

  def handle_event("search", %{"value" => query}, socket) do
    {:noreply, socket |> assign(:query, query) |> load_rows()}
  end

  defp load_rows(socket) do
    %{current_scope: scope, today: today, tab: tab, query: query} = socket.assigns

    obligations =
      case tab do
        :my_work -> Obligations.list_my_work(scope)
        :team -> Obligations.list_team_overview(scope)
      end

    rows =
      obligations
      |> filter(query)
      |> Enum.map(fn obligation ->
        %{
          obligation: obligation,
          urgency: Urgency.classify(obligation.obligation_type, obligation.due_by, today)
        }
      end)
      |> Enum.sort_by(fn %{obligation: o, urgency: u} -> {@urgency_rank[u], o.due_by} end)

    assign(socket, :rows, rows)
  end

  defp filter(obligations, ""), do: obligations

  defp filter(obligations, query) do
    q = String.downcase(query)
    Enum.filter(obligations, &String.contains?(String.downcase(&1.title), q))
  end
end
