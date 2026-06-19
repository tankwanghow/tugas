defmodule ArgusWeb.ObligationStatusBadge do
  @moduledoc """
  Renders completed / cancelled badges for non-live obligation cycles.
  """
  use Phoenix.Component

  attr :cycle_status, :atom, required: true
  attr :detail, :string, default: nil

  def obligation_status_badge(assigns) do
    ~H"""
    <div :if={@cycle_status == :completed} class="badge badge-success badge-sm gap-1">
      Completed<p :if={@detail} class="font-normal text-xs">{@detail}</p>
    </div>
    <span :if={@cycle_status == :cancelled} class="badge badge-error badge-sm">Cancelled</span>
    """
  end
end
