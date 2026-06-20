defmodule ArgusWeb.ObligationStatusBadge do
  @moduledoc """
  Renders completed / skipped / series-ended badges for non-live obligation cycles.
  """
  use Phoenix.Component

  attr :cycle_status, :atom, required: true
  attr :detail, :string, default: nil
  attr :in_error, :boolean, default: false

  def obligation_status_badge(assigns) do
    ~H"""
    <div
      :if={@cycle_status == :completed}
      class={[
        "-space-y-1 text-center border rounded-xl p-1",
        if(@in_error, do: "bg-error", else: "bg-success")
      ]}
    >
      <div class="font-bold text-xs">Completed</div>
      <div :if={@detail} class="text-[12px]">{@detail}</div>
    </div>
    <span :if={@cycle_status == :skipped} class="badge badge-warning badge-sm">Skipped</span>
    <span :if={@cycle_status == :series_ended} class="badge badge-neutral badge-sm">
      Series ended
    </span>
    """
  end
end
