defmodule ArgusWeb.EventMeta do
  @moduledoc """
  Renders an obligation's latest (current) event as a compact line: a status
  badge, the event count, who acted, and a truncated note. Shared by the
  desktop dashboard rows and the mobile obligation card.
  """
  use Phoenix.Component

  attr :event, :map, required: true
  attr :event_count, :integer, required: true
  attr :show_actor, :boolean, default: true

  def event_meta(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs text-base-content/60 mt-1">
      <span class={["badge badge-xs", status_badge_class(@event.status)]}>
        {humanize_status(@event.status)}
      </span>
      <span>{event_count_label(@event_count)}</span>
      <span :if={@show_actor and @event.status_by}>by {@event.status_by.email}</span>
      <span :if={@event.note} class="truncate max-w-[16rem] italic text-base-content/50">
        “{truncate_note(@event.note)}”
      </span>
    </div>
    """
  end

  defp humanize_status("in_progress"), do: "In progress"
  defp humanize_status("series_ended"), do: "Series ended"
  defp humanize_status(status), do: String.capitalize(status)

  defp status_badge_class("in_progress"), do: "badge-warning badge-soft"
  defp status_badge_class("done"), do: "badge-success badge-soft"
  defp status_badge_class("skipped"), do: "badge-warning badge-soft"
  defp status_badge_class("series_ended"), do: "badge-neutral badge-soft"
  defp status_badge_class("cancelled"), do: "badge-error badge-soft"
  defp status_badge_class(_), do: "badge-ghost"

  defp event_count_label(1), do: "1 event"
  defp event_count_label(count), do: "#{count} events"

  defp truncate_note(note) when is_binary(note) do
    if String.length(note) > 72, do: String.slice(note, 0, 69) <> "…", else: note
  end
end
