defmodule ArgusWeb.MobileLive.Components do
  @moduledoc """
  Shared presentational components for the mobile (`/m/:entity_slug`) UI.
  """
  use ArgusWeb, :html

  @doc """
  A touch-friendly obligation card linking to the mobile show page, with a
  left accent and urgency badge sized for field use.
  """
  attr :row, :map, required: true, doc: "%{obligation: ..., urgency: ..., cycle_status: ...}"
  attr :today, Date, required: true
  attr :slug, :string, required: true

  def obligation_card(assigns) do
    ~H"""
    <li
      id={"m-ob-#{@row.obligation.id}"}
      data-event-count={@row.event_count}
      data-event-status={@row.latest_event && @row.latest_event.status}
    >
      <.link
        navigate={~p"/m/#{@slug}/obligations/#{@row.obligation.id}"}
        class={["block rounded-box border border-base-300 p-3 border-l-4", accent(@row)]}
      >
        <div class="flex items-center justify-between gap-2">
          <span class="font-medium truncate">{@row.obligation.title}</span>
          <.obligation_status_badge
            :if={@row.cycle_status != :live}
            cycle_status={@row.cycle_status}
            in_error={!is_nil(@row.obligation.completed_in_error_at)}
          />
          <.urgency_badge
            :if={@row.cycle_status == :live}
            tier={@row.tier}
            due_by={@row.obligation.due_by}
            today={@today}
          />
        </div>
        <div class="text-sm text-base-content/60 truncate mt-1">
          {@row.obligation.obligation_type.name}
        </div>
        <div class={["text-xs mt-0.5", text_color(@row)]}>
          {card_meta(@row)}
        </div>
        <.event_meta
          :if={@row.latest_event}
          event={@row.latest_event}
          event_count={@row.event_count}
          show_actor={false}
        />
      </.link>
    </li>
    """
  end

  defp accent(%{cycle_status: status}) when status in [:skipped, :series_ended],
    do: "border-error/60"

  defp accent(%{cycle_status: :completed}), do: "border-success/60"
  defp accent(%{tier: tier}), do: tier_border(tier)
  defp accent(_), do: "border-transparent"

  defp text_color(%{cycle_status: status}) when status in [:completed, :skipped, :series_ended],
    do: "text-base-content/50"

  defp text_color(%{tier: tier}) when tier in [:overdue, :critical], do: "text-error"
  defp text_color(%{tier: tier}) when tier in [:due_soon, :approaching], do: "text-warning"
  defp text_color(_), do: "text-base-content/50"

  defp card_meta(%{cycle_status: :completed, obligation: o}) do
    "completed #{format_datetime(o.completed_at)} · due #{format_date(o.due_by)}"
  end

  defp card_meta(%{cycle_status: status, obligation: o})
       when status in [:skipped, :series_ended] do
    "#{humanize_cycle(status)} · due #{format_date(o.due_by)}"
  end

  defp card_meta(%{obligation: o}) do
    "due #{format_date(o.due_by)}"
  end

  defp humanize_cycle(:series_ended), do: "series ended"
  defp humanize_cycle(_), do: "skipped"
end
