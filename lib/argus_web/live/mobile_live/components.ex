defmodule ArgusWeb.MobileLive.Components do
  @moduledoc """
  Shared presentational components for the mobile (`/m/:entity_slug`) UI.
  """
  use ArgusWeb, :html

  @doc """
  A touch-friendly obligation card linking to the mobile show page, with a
  left accent and urgency badge sized for field use.
  """
  attr :row, :map, required: true, doc: "%{obligation: ..., urgency: ...}"
  attr :today, Date, required: true
  attr :slug, :string, required: true

  def obligation_card(assigns) do
    ~H"""
    <li id={"m-ob-#{@row.obligation.id}"}>
      <.link
        navigate={~p"/m/#{@slug}/obligations/#{@row.obligation.id}"}
        class={["block rounded-box border border-base-300 p-3 border-l-4", accent(@row.urgency)]}
      >
        <div class="flex items-center justify-between gap-2">
          <span class="font-medium truncate">{@row.obligation.title}</span>
          <.urgency_badge urgency={@row.urgency} />
        </div>
        <div class="text-sm text-base-content/60 truncate mt-1">
          {@row.obligation.obligation_type.name}
        </div>
        <div class={["text-xs mt-0.5", text_color(@row.urgency)]}>
          due {format_date(@row.obligation.due_by)} · {due_label(@row.obligation.due_by, @today)}
        </div>
      </.link>
    </li>
    """
  end

  defp accent(:overdue), do: "border-error"
  defp accent(:due_soon), do: "border-warning"
  defp accent(_), do: "border-transparent"

  defp text_color(:overdue), do: "text-error"
  defp text_color(:due_soon), do: "text-warning"
  defp text_color(_), do: "text-base-content/50"
end
