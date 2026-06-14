defmodule ArgusWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use ArgusWeb, :html

  embed_templates "page_html/*"

  @doc false
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :body, :string, required: true

  def feature(assigns) do
    ~H"""
    <div class="bg-ink2 p-7 hover:bg-glass transition-colors">
      <div class="size-11 rounded-xl b-amber border grid place-items-center">
        <.icon name={@icon} class="size-5 c-amber" />
      </div>
      <h3 class="font-display text-xl mt-5">{@title}</h3>
      <p class="c-dim text-sm leading-relaxed mt-2">{@body}</p>
    </div>
    """
  end
end
