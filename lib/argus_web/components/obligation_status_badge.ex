defmodule ArgusWeb.ObligationStatusBadge do
  @moduledoc """
  Renders completed / skipped / series-ended badges for non-live obligation cycles.

  Every badge shares the same shape — a bold status word above its terminal date —
  and differs only in colour. The date is derived from the obligation: `completed_at`
  for Completed, `closed_at` for Skipped and Series ended.
  """
  use Phoenix.Component

  attr :cycle_status, :atom, required: true
  attr :obligation, :any, required: true
  attr :in_error, :boolean, default: false

  def obligation_status_badge(assigns) do
    assigns =
      assigns
      |> assign(:label, label(assigns.cycle_status))
      |> assign(:color, color(assigns.cycle_status, assigns.in_error))
      |> assign(:date, terminal_date(assigns.cycle_status, assigns.obligation))

    ~H"""
    <div :if={@label} class={["-space-y-1 text-center border rounded-xl p-1", @color]}>
      <div class="font-bold text-xs">{@label}</div>
      <div :if={@date} class="text-[12px]">{@date}</div>
    </div>
    """
  end

  defp label(:completed), do: "Completed"
  defp label(:skipped), do: "Skipped"
  defp label(:series_ended), do: "Series ended"
  defp label(_), do: nil

  defp color(:completed, true), do: "bg-error"
  defp color(:completed, _), do: "bg-success"
  defp color(:skipped, _), do: "bg-warning"
  defp color(:series_ended, _), do: "bg-neutral text-neutral-content"
  defp color(_, _), do: ""

  defp terminal_date(:completed, %{completed_at: at}), do: fmt(at)
  defp terminal_date(:skipped, %{closed_at: at}), do: fmt(at)
  defp terminal_date(:series_ended, %{closed_at: at}), do: fmt(at)
  defp terminal_date(_, _), do: nil

  defp fmt(%DateTime{} = dt), do: dt |> DateTime.to_date() |> Calendar.strftime("%d %b %Y")
  defp fmt(_), do: nil
end
