defmodule TugasWeb.DutySeriesNav do
  @moduledoc false

  use Phoenix.Component

  import TugasWeb.CoreComponents, only: [format_date: 2]

  use TugasWeb, :verified_routes

  attr :id, :string, default: "duty-series-nav"
  attr :entity_slug, :string, required: true
  attr :variant, :atom, values: [:desktop, :mobile], default: :desktop
  attr :previous, :map, default: nil
  attr :next, :map, default: nil

  def duty_series_nav(assigns) do
    ~H"""
    <header
      :if={@previous || @next}
      id={@id}
      class={[
        "flex w-full items-center gap-3 border-b border-base-300",
        @variant == :mobile && "mb-2 pb-2",
        @variant == :desktop && "mb-3 pb-2",
        nav_justify(@previous, @next)
      ]}
      aria-label="Series cycle navigation"
    >
      <.link
        :if={@previous}
        id={"#{@id}-previous"}
        navigate={duty_show_path(@variant, @entity_slug, @previous.id)}
        class={series_link_class(@variant)}
      >
        <span class="font-semibold text-primary">{sibling_label(@previous)}</span><span class="text-primary/70">.previous</span>
      </.link>
      <.link
        :if={@next}
        id={"#{@id}-next"}
        navigate={duty_show_path(@variant, @entity_slug, @next.id)}
        class={[series_link_class(@variant), "text-right"]}
      >
        <span class="text-primary/70">next.</span><span class="font-semibold text-primary">{sibling_label(@next)}</span>
      </.link>
    </header>
    """
  end

  defp series_link_class(:mobile) do
    "inline-flex min-w-0 max-w-[48%] truncate rounded-lg border border-primary/35 bg-primary/8 px-2.5 py-2 font-mono text-xs tracking-tight text-primary shadow-sm transition hover:border-primary hover:bg-primary/15 hover:shadow active:scale-[0.98]"
  end

  defp series_link_class(_) do
    "inline-flex min-w-0 max-w-[48%] truncate rounded-lg border border-primary/35 bg-primary/8 px-3 py-1.5 font-mono text-sm tracking-tight text-primary shadow-sm transition hover:border-primary hover:bg-primary/15 hover:shadow active:scale-[0.98]"
  end

  defp nav_justify(previous, next) when not is_nil(previous) and not is_nil(next),
    do: "justify-between"

  defp nav_justify(previous, _next) when not is_nil(previous), do: "justify-start"
  defp nav_justify(_previous, next) when not is_nil(next), do: "justify-end"
  defp nav_justify(_, _), do: "justify-between"

  defp sibling_label(%{due_by: %Date{} = due}), do: format_date(due, :short)
  defp sibling_label(_), do: "Someday"

  defp duty_show_path(:mobile, slug, id), do: ~p"/m/#{slug}/duties/#{id}"
  defp duty_show_path(_, slug, id), do: ~p"/entities/#{slug}/duties/#{id}"
end