defmodule TugasWeb.DutyCalendar do
  @moduledoc false
  use Phoenix.Component

  import TugasWeb.UrgencyBadge, only: [tier_border: 1]

  use Phoenix.VerifiedRoutes,
    endpoint: TugasWeb.Endpoint,
    router: TugasWeb.Router,
    statics: TugasWeb.static_paths()

  alias TugasWeb.DashboardLive.CalendarHelpers

  attr :grid, :map, required: true
  attr :grouped, :map, required: true
  attr :someday_rows, :list, required: true
  attr :slug, :string, required: true
  attr :variant, :atom, default: :desktop
  attr :day_modal_date, :any, default: nil
  attr :day_modal_rows, :list, default: []
  attr :day_modal_holidays, :list, default: []
  attr :hide_someday_strip?, :boolean, default: false
  attr :someday_collapsed?, :boolean, default: false

  def duty_calendar(assigns) do
    assigns =
      assigns
      |> assign(:max_chips, CalendarHelpers.max_chips_per_day(assigns.variant))
      |> assign(:max_someday, CalendarHelpers.max_someday_chips(assigns.variant))
      |> assign(:mobile?, assigns.variant == :mobile)
      |> assign(:show_someday_strip?, !assigns.hide_someday_strip? && assigns.someday_rows != [])

    ~H"""
    <div id="duty-calendar" class={calendar_root_class(@mobile?)}>
      <div class={calendar_grid_wrapper_class(@mobile?)}>
        <div class="flex h-full min-h-0 flex-col gap-px rounded-lg overflow-hidden border border-base-300 bg-base-300">
          <div class="grid shrink-0 grid-cols-7 gap-px">
            <.weekday_headers mobile?={@mobile?} />
          </div>
          <div id="calendar-body-grid" class="flex min-h-0 flex-1 flex-col gap-px">
            <.calendar_week_rows
              grid={@grid}
              grouped={@grouped}
              slug={@slug}
              variant={@variant}
              mobile?={@mobile?}
              max_chips={@max_chips}
            />
          </div>
        </div>
      </div>

      <section
        :if={@show_someday_strip?}
        id="someday-strip"
        class="shrink-0 rounded-lg border border-base-300 bg-base-200/40 p-3 space-y-2"
      >
        <div class="flex items-center justify-between">
          <h3 class="text-sm font-semibold text-base-content/70">Someday</h3>
          <.collapse_toggle panel="someday" collapsed?={@someday_collapsed?} label="Someday" />
        </div>
        <div :if={!@someday_collapsed?} class={someday_chips_class(@mobile?)}>
          <%= for {row, idx} <- Enum.with_index(@someday_rows) do %>
            <.duty_chip
              :if={idx < @max_someday}
              row={row}
              slug={@slug}
              variant={@variant}
              layout={:someday}
            />
          <% end %>
          <%= if length(@someday_rows) > @max_someday do %>
            <% extra = length(@someday_rows) - @max_someday %>
            <.link
              id="someday-more"
              navigate={
                duties_path(@variant, @slug, lifecycle: "live", sort: "someday", q: "", mine: "false")
              }
              class="text-xs text-primary hover:underline px-0.5 shrink-0"
            >
              +{extra} more
            </.link>
          <% end %>
        </div>
      </section>

      <.day_modal
        :if={@day_modal_date}
        date={@day_modal_date}
        rows={@day_modal_rows}
        holidays={@day_modal_holidays}
        slug={@slug}
        variant={@variant}
      />
    </div>
    """
  end

  def new_todo_modal(assigns) do
    ~H"""
    <div id="new-todo-modal" class="modal modal-open">
      <div class="modal-box max-w-md">
        <h3 class="text-lg font-bold mb-2">New todo</h3>
        <form id="new-todo-form" phx-submit="create_todo">
          <input
            type="text"
            name="title"
            placeholder="What needs doing?"
            class="input w-full"
            maxlength="200"
            autocomplete="off"
            required
          />
          <div class="modal-action">
            <button type="button" class="btn" phx-click="close_new_todo">Cancel</button>
            <button type="submit" class="btn btn-primary">Add todo</button>
          </div>
        </form>
      </div>
      <button class="modal-backdrop" type="button" phx-click="close_new_todo" aria-label="Close" />
    </div>
    """
  end

  attr :rows, :list, required: true
  attr :slug, :string, required: true
  attr :variant, :atom, default: :mobile

  def mobile_someday_panel(assigns) do
    assigns = assign(assigns, :max_someday, CalendarHelpers.max_someday_chips(:mobile))

    ~H"""
    <section id="m-dashboard-someday" class="h-full min-h-0 flex flex-col px-1">
      <h2 class="shrink-0 text-lg font-semibold text-base-content/80 pb-2">Someday</h2>
      <p :if={@rows == []} class="text-sm text-base-content/60">
        No someday duties.
      </p>
      <ul :if={@rows != []} class="min-h-0 flex-1 space-y-2 overflow-y-auto">
        <li :for={row <- Enum.take(@rows, @max_someday)}>
          <.duty_chip
            row={row}
            slug={@slug}
            variant={@variant}
            id_prefix="someday-panel-duty-chip"
            layout={:list}
          />
        </li>
        <li :if={length(@rows) > @max_someday}>
          <.link
            id="someday-more"
            navigate={
              duties_path(:mobile, @slug, lifecycle: "live", sort: "someday", q: "", mine: "false")
            }
            class="text-xs text-primary hover:underline px-0.5"
          >
            +{length(@rows) - @max_someday} more
          </.link>
        </li>
      </ul>
    </section>
    """
  end

  attr :rows, :list, required: true
  attr :slug, :string, required: true
  attr :variant, :atom, default: :desktop
  attr :collapsed?, :boolean, default: false

  def urgent_panel(assigns) do
    assigns =
      assigns
      |> assign(:mobile?, assigns.variant == :mobile)
      |> assign(:max_urgent, CalendarHelpers.max_urgent_chips())

    ~H"""
    <section id={urgent_panel_id(@mobile?)} class={urgent_panel_class(@mobile?, @collapsed?)}>
      <.collapsed_rail :if={!@mobile? and @collapsed?} panel="urgent" label="Urgent" side={:left} />

      <.panel_header
        :if={@mobile? or !@collapsed?}
        title="Urgent"
        mobile?={@mobile?}
        panel="urgent"
        collapsed?={@collapsed?}
      />

      <div :if={@mobile? or !@collapsed?} class="flex min-h-0 flex-1 flex-col">
        <p :if={@rows == []} class="text-sm text-base-content/60">
          Nothing overdue or due soon.
        </p>

        <ul :if={@rows != []} class="min-h-0 flex-1 space-y-2 overflow-y-auto">
          <li :for={row <- Enum.take(@rows, @max_urgent)}>
            <.duty_chip
              row={row}
              slug={@slug}
              variant={@variant}
              id_prefix={urgent_chip_prefix(@mobile?)}
              layout={:list}
            />
          </li>
        </ul>

        <.link
          :if={length(@rows) > @max_urgent}
          id="urgent-more"
          navigate={
            duties_path(@variant, @slug, lifecycle: "live", sort: "urgency", q: "", mine: "false")
          }
          class="shrink-0 text-xs text-primary hover:underline px-0.5 pt-1"
        >
          +{length(@rows) - @max_urgent} more
        </.link>
      </div>
    </section>
    """
  end

  defp urgent_panel_id(true), do: "m-dashboard-urgent"
  defp urgent_panel_id(false), do: "urgent-panel"

  defp urgent_chip_prefix(true), do: "urgent-panel-duty-chip"
  defp urgent_chip_prefix(false), do: "urgent-duty-chip"

  defp urgent_panel_class(true, _collapsed?), do: "h-full min-h-0 flex flex-col px-1"

  defp urgent_panel_class(false, true),
    do:
      "flex h-full min-h-0 flex-col items-center rounded-lg border border-base-300 bg-base-200/40 p-1"

  defp urgent_panel_class(false, false),
    do:
      "flex h-full min-h-0 min-w-0 flex-col rounded-lg border border-base-300 bg-base-200/40 p-3"

  defp duties_path(:mobile, slug, params), do: ~p"/m/#{slug}/duties?#{params}"
  defp duties_path(_variant, slug, params), do: ~p"/entities/#{slug}/duties?#{params}"

  attr :title, :string, required: true
  attr :mobile?, :boolean, required: true
  attr :panel, :string, required: true
  attr :collapsed?, :boolean, default: false

  defp panel_header(%{mobile?: true} = assigns) do
    ~H"""
    <h2 class="shrink-0 text-lg font-semibold text-base-content/80 pb-2">{@title}</h2>
    """
  end

  defp panel_header(%{mobile?: false} = assigns) do
    ~H"""
    <div class="flex shrink-0 items-center justify-between pb-2">
      <h3 class="text-sm font-semibold text-base-content/70">{@title}</h3>
      <.collapse_toggle panel={@panel} collapsed?={@collapsed?} label={@title} />
    </div>
    """
  end

  attr :panel, :string, required: true
  attr :label, :string, required: true
  attr :side, :atom, default: :left

  defp collapsed_rail(assigns) do
    ~H"""
    <button
      type="button"
      id={"#{@panel}-collapse"}
      phx-click="toggle_panel"
      phx-value-panel={@panel}
      class="flex h-full w-full flex-col items-center gap-2 text-base-content/60 hover:text-base-content"
      aria-label={"Expand #{@label}"}
      aria-expanded="false"
    >
      <span class="text-xs leading-none">{if @side == :left, do: "»", else: "«"}</span>
      <span class="text-sm font-semibold [writing-mode:vertical-rl] rotate-180">
        {@label}
      </span>
    </button>
    """
  end

  attr :panel, :string, required: true
  attr :collapsed?, :boolean, required: true
  attr :label, :string, required: true

  defp collapse_toggle(assigns) do
    ~H"""
    <button
      type="button"
      id={"#{@panel}-collapse"}
      phx-click="toggle_panel"
      phx-value-panel={@panel}
      class="text-xs leading-none text-base-content/60 hover:text-base-content"
      aria-label={"Toggle #{@label}"}
      aria-expanded={to_string(!@collapsed?)}
    >
      {if @collapsed?, do: "▸", else: "▾"}
    </button>
    """
  end

  attr :mobile?, :boolean, required: true

  defp weekday_headers(assigns) do
    ~H"""
    <div
      :for={label <- ~w(Sun Mon Tue Wed Thu Fri Sat)}
      class={[
        "bg-base-200 px-2 py-1.5 text-center font-semibold text-base-content/70",
        @mobile? && "text-[10px]",
        !@mobile? && "text-xs"
      ]}
    >
      {label}
    </div>
    """
  end

  attr :grid, :map, required: true
  attr :grouped, :map, required: true
  attr :slug, :string, required: true
  attr :variant, :atom, required: true
  attr :mobile?, :boolean, required: true
  attr :max_chips, :integer, required: true

  defp calendar_week_rows(assigns) do
    ~H"""
    <div
      :for={{week, week_idx} <- Enum.with_index(@grid.weeks)}
      id={"calendar-week-#{week_idx}"}
      class="grid min-h-0 flex-1 basis-0 grid-cols-7 gap-px"
    >
      <.calendar_day_cell
        :for={cell <- week}
        cell={cell}
        grouped={@grouped}
        slug={@slug}
        variant={@variant}
        mobile?={@mobile?}
        max_chips={@max_chips}
      />
    </div>
    """
  end

  attr :cell, :map, required: true
  attr :grouped, :map, required: true
  attr :slug, :string, required: true
  attr :variant, :atom, required: true
  attr :mobile?, :boolean, required: true
  attr :max_chips, :integer, required: true

  defp calendar_day_cell(assigns) do
    ~H"""
    <div
      id={"calendar-day-#{@cell.date}"}
      phx-click="open_day_modal"
      phx-value-date={Date.to_iso8601(@cell.date)}
      class={[
        "bg-base-100 p-1 space-y-0.5 min-w-0 overflow-hidden cursor-pointer active:bg-base-200/80",
        cell_class(@mobile?),
        !@cell.in_month? && "bg-base-200/40 text-base-content/40",
        @cell.holidays != [] && @cell.in_month? && "bg-info/10",
        @cell.today? && "ring-2 ring-inset ring-primary/40"
      ]}
    >
      <div class="flex min-w-0 items-baseline gap-0.5 px-0.5">
        <span class={[
          "shrink-0 font-medium",
          @mobile? && "text-[10px]",
          !@mobile? && "text-xs",
          date_accent_class(@cell)
        ]}>
          {@cell.date.day}
        </span>
        <span
          :for={holiday <- Enum.take(@cell.holidays, 1)}
          id={"calendar-holiday-#{@cell.date}"}
          class={[
            "min-w-0 truncate font-medium text-info",
            @mobile? && "text-[9px] leading-tight",
            !@mobile? && "text-[10px] leading-tight"
          ]}
          title={holiday.label}
        >
          {holiday.label}
        </span>
      </div>
      <%= for {row, idx} <- Enum.with_index(Map.get(@grouped, @cell.date, [])) do %>
        <.duty_chip
          :if={idx < @max_chips}
          row={row}
          slug={@slug}
          variant={@variant}
          layout={:calendar}
        />
      <% end %>
      <%= if length(Map.get(@grouped, @cell.date, [])) > @max_chips do %>
        <% extra = length(Map.get(@grouped, @cell.date, [])) - @max_chips %>
        <span
          id={"calendar-day-more-#{@cell.date}"}
          class={[
            "px-0.5 text-base-content/60",
            @mobile? && "text-[10px]",
            !@mobile? && "text-xs"
          ]}
        >
          +{extra} more
        </span>
      <% end %>
    </div>
    """
  end

  attr :row, :map, required: true
  attr :slug, :string, required: true
  attr :variant, :atom, default: :desktop
  attr :id_prefix, :string, default: "duty-chip"
  attr :layout, :atom, default: :calendar

  defp duty_chip(assigns) do
    assigns =
      assigns
      |> assign(:show_type?, show_type_name?(assigns.variant, assigns.layout))
      |> assign(:clickable?, chip_clickable?(assigns.variant, assigns.layout))

    ~H"""
    <%= if @clickable? do %>
      <.link
        id={"#{@id_prefix}-#{@row.duty.id}"}
        navigate={duty_show_path(@variant, @slug, @row.duty.id)}
        class={chip_class(@variant, @layout, @row.tier)}
      >
        <span class={chip_title_class(@variant, @layout)}>{@row.duty.title}</span>
        <span :if={@show_type?} class={chip_type_class(@variant, @layout)}>
          {@row.duty.duty_type.name}
        </span>
      </.link>
    <% else %>
      <span
        id={"#{@id_prefix}-#{@row.duty.id}"}
        class={chip_class(@variant, @layout, @row.tier)}
      >
        <span class={chip_title_class(@variant, @layout)}>{@row.duty.title}</span>
        <span :if={@show_type?} class={chip_type_class(@variant, @layout)}>
          {@row.duty.duty_type.name}
        </span>
      </span>
    <% end %>
    """
  end

  attr :date, :any, required: true
  attr :rows, :list, required: true
  attr :holidays, :list, default: []
  attr :slug, :string, required: true
  attr :variant, :atom, default: :desktop

  defp day_modal(assigns) do
    ~H"""
    <div id="day-modal" class="modal modal-open">
      <div class="modal-box max-w-md">
        <h3 class="font-bold text-lg">
          {Calendar.strftime(@date, "%A, %B %-d")}
        </h3>
        <ul :if={@holidays != []} class="mt-2 space-y-1 text-sm text-info">
          <li :for={holiday <- @holidays}>{holiday.label}</li>
        </ul>
        <p :if={@rows == []} id="day-modal-empty" class="mt-3 text-sm text-base-content/60">
          No duties on this day.
        </p>
        <ul :if={@rows != []} class="mt-3 space-y-2 max-h-[70vh] overflow-y-auto">
          <li :for={row <- @rows}>
            <.duty_chip
              row={row}
              slug={@slug}
              variant={@variant}
              id_prefix="day-modal-duty-chip"
              layout={:list}
            />
          </li>
        </ul>
        <div class="modal-action">
          <button type="button" class="btn" phx-click="close_day_modal">Close</button>
        </div>
      </div>
      <button class="modal-backdrop" type="button" phx-click="close_day_modal" aria-label="Close" />
    </div>
    """
  end

  defp calendar_root_class(true), do: "flex h-full min-h-0 flex-col"
  defp calendar_root_class(false), do: "flex h-full min-h-0 flex-col gap-4"

  defp calendar_grid_wrapper_class(true), do: "min-h-0 flex-1"
  defp calendar_grid_wrapper_class(false), do: "min-h-0 flex-1"

  defp cell_class(_mobile?), do: "h-full min-h-0"

  defp date_accent_class(cell) do
    if sunday_or_holiday?(cell), do: "text-error", else: nil
  end

  defp sunday_or_holiday?(%{date: date, holidays: holidays}) do
    Date.day_of_week(date, :sunday) == 1 or holidays != []
  end

  defp someday_chips_class(true), do: "flex gap-1 overflow-x-auto flex-nowrap items-center"
  defp someday_chips_class(false), do: "flex flex-wrap gap-1 items-center"

  defp chip_class(variant, layout, tier) do
    [
      chip_text_class(variant, layout),
      chip_surface_class(variant, layout),
      chip_layout_class(layout),
      chip_tier_border(variant, layout, tier)
    ]
  end

  defp chip_clickable?(_, :calendar), do: false
  defp chip_clickable?(_, _), do: true

  defp chip_text_class(:mobile, :list), do: "block text-base leading-snug"
  defp chip_text_class(:mobile, _), do: "block text-[10px]"
  defp chip_text_class(_, _), do: "block text-xs"

  defp chip_surface_class(:mobile, :list),
    do: "tugas-duty-chip-hover px-3 py-3 min-h-12 rounded-lg border border-base-300 bg-base-100"

  defp chip_surface_class(_, :calendar),
    do: "px-1.5 py-0.5 rounded pointer-events-none"

  defp chip_surface_class(_, :someday),
    do: "tugas-duty-chip-hover px-1.5 py-0.5 rounded border border-base-300 bg-base-100"

  defp chip_surface_class(_, :list),
    do: "tugas-duty-chip-hover px-3 py-2 rounded-lg border border-base-300 bg-base-100"

  defp chip_surface_class(_, _), do: "px-1.5 py-0.5 rounded hover:bg-base-200"

  defp chip_title_class(:mobile, :list), do: "font-medium block"
  defp chip_title_class(_, :calendar), do: "font-medium block overflow-hidden whitespace-nowrap"
  defp chip_title_class(_, _), do: "font-medium block truncate"

  defp chip_type_class(:mobile, :list), do: "mt-0.5 block truncate text-sm text-info"
  defp chip_type_class(_, :list), do: "mt-0.5 block truncate text-xs text-info"

  defp chip_tier_border(:mobile, :list, tier), do: ["border-l-4", tier_border(tier)]
  defp chip_tier_border(_, _, tier), do: ["border-l-2", tier_border(tier)]

  defp chip_layout_class(:someday), do: "block w-44 max-w-44 shrink-0"
  defp chip_layout_class(:list), do: "block w-full min-w-0"
  defp chip_layout_class(_), do: "block w-full min-w-0"

  defp show_type_name?(_, :list), do: true
  defp show_type_name?(_, _), do: false

  defp duty_show_path(:mobile, slug, id), do: ~p"/m/#{slug}/duties/#{id}"
  defp duty_show_path(_, slug, id), do: ~p"/entities/#{slug}/duties/#{id}"
end
