defmodule ArgusWeb.EventMeta do
  @moduledoc """
  Renders an obligation's latest (current) event as a compact line: a status
  badge, the event count, who acted, and a truncated note. Shared by the
  desktop dashboard rows and the mobile obligation card.
  """
  use Phoenix.Component

  import ArgusWeb.CoreComponents, only: [user_label: 1]

  attr :event, :map, required: true
  attr :event_count, :integer, required: true
  attr :show_actor, :boolean, default: true

  def event_meta(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-x-1 gap-y-0.5 text-sm text-base-content/60 mt-1">
      <span
        :if={@event.status in ["open", "in_progress"]}
        class={["badge badge-xs", status_badge_class(@event.status)]}
      >
        {humanize_status(@event.status)}
      </span>
      <span :if={@show_actor and @event.status_by}>by {user_label(@event.status_by)}</span>
      <span :if={@event.note} class="truncate max-w-[15rem] italic text-base-content/100">
        “{truncate_note(@event.note)}”
      </span>
    </div>
    """
  end

  # Only open / in_progress reach here — terminal states are shown by the
  # cycle's status badge, so their event badge is suppressed (see event_meta/1).
  defp humanize_status("in_progress"), do: "In progress"
  defp humanize_status(status), do: String.capitalize(status)

  defp status_badge_class("in_progress"), do: "badge-warning badge-soft"
  defp status_badge_class(_), do: "badge-ghost"

  defp truncate_note(note) when is_binary(note) do
    if String.length(note) > 72, do: String.slice(note, 0, 69) <> "…", else: note
  end
end
