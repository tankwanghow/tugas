defmodule ArgusWeb.ObligationDocumentThumb do
  @moduledoc false

  use Phoenix.Component

  import ArgusWeb.CoreComponents

  alias ArgusWeb.ObligationLive.DocumentHelpers

  @doc """
  Full-width thumb grid: auto-fill columns sized to the parent (no fixed column count).
  """
  def thumb_grid_classes(:mobile),
    do: "mt-2 grid w-full gap-1 grid-cols-[repeat(auto-fill,minmax(8rem,1fr))]"

  def thumb_grid_classes(:desktop),
    do:
      "mt-2 grid w-full gap-1.5 grid-cols-[repeat(auto-fill,minmax(10rem,1fr))] lg:grid-cols-[repeat(auto-fill,minmax(15rem,1fr))]"

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :href, :string, default: nil
  attr :name, :string, default: ""
  attr :empty?, :boolean, default: false
  attr :manage_id, :string, default: nil

  def doc_thumb_tile(assigns) do
    assigns =
      assigns
      |> assign(:kind, DocumentHelpers.file_kind(assigns.name))
      |> assign(:manage_id, assigns.manage_id || assigns.id)

    ~H"""
    <div id={@id} class="flex min-w-0 flex-col gap-0.5">
      <div class="relative aspect-square overflow-hidden rounded-box border border-base-300 bg-base-200">
        <%= if @empty? do %>
          <button
            id={@manage_id}
            type="button"
            phx-click="open_completion_modal"
            phx-value-slot={@label}
            class="flex h-full w-full items-center justify-center border-2 border-dashed border-base-300 text-base-content/50 transition-colors hover:border-primary hover:text-primary cursor-pointer"
            title="Upload completion document"
          >
            <.icon name="hero-plus-mini" class="size-6" />
          </button>
        <% else %>
          <a
            href={@href}
            target="_blank"
            rel="noopener"
            data-doc-preview
            data-doc-kind={@kind}
            data-doc-name={@name}
            class="absolute inset-0 z-0 flex items-center justify-center"
            aria-label={@name}
          >
            <.thumb_media href={@href} name={@name} kind={@kind} id={"#{@id}-media"} />
          </a>
          <button
            :if={@manage_id}
            id={@manage_id}
            type="button"
            phx-click="open_completion_modal"
            phx-value-slot={@label}
            class="btn btn-xs btn-circle btn-ghost absolute top-0.5 right-0.5 z-10 bg-base-100/80"
            aria-label={"Manage #{@label}"}
          >
            <.icon name="hero-ellipsis-horizontal-mini" class="size-4" />
          </button>
        <% end %>
      </div>
      <p class="truncate text-center text-[10px] leading-tight text-base-content/80">{@label}</p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :href, :string, required: true
  attr :name, :string, required: true

  def doc_thumb_preview(assigns) do
    assigns = assign(assigns, :kind, DocumentHelpers.file_kind(assigns.name))

    ~H"""
    <div id={@id} class="flex min-w-0 flex-col gap-0.5">
      <div class="relative aspect-square overflow-hidden rounded-box border border-base-300 bg-base-200">
        <a
          href={@href}
          target="_blank"
          rel="noopener"
          data-doc-preview
          data-doc-kind={@kind}
          data-doc-name={@name}
          class="absolute inset-0 z-0 flex items-center justify-center"
          aria-label={@name}
        >
          <.thumb_media href={@href} name={@name} kind={@kind} id={"#{@id}-media"} />
        </a>
      </div>
      <p class="truncate text-center text-[10px] leading-tight text-base-content/80">{@label}</p>
    </div>
    """
  end

  attr :href, :string, default: nil
  attr :name, :string, required: true
  attr :kind, :atom, required: true
  attr :id, :string, required: true

  defp thumb_media(assigns) do
    ~H"""
    <%= cond do %>
      <% @kind == :image and @href -> %>
        <img src={@href} alt={@name} loading="lazy" class="h-full w-full object-cover" />
      <% @kind == :video and @href -> %>
        <div class="relative h-full w-full">
          <video muted playsinline preload="metadata" class="h-full w-full object-cover">
            <source src={@href} />
          </video>
          <span class="pointer-events-none absolute inset-0 flex items-center justify-center text-3xl text-white/90 drop-shadow">
            ▶
          </span>
        </div>
      <% @kind == :pdf and @href -> %>
        <canvas
          id={@id}
          phx-hook="PdfThumb"
          phx-update="ignore"
          data-src={@href}
          class="h-full w-full object-cover"
        />
      <% true -> %>
        <div class="flex h-full w-full min-w-0 flex-col items-center justify-center gap-0.5 p-1.5 text-center">
          <.icon name={doc_kind_icon(@kind)} class="size-7 shrink-0 text-base-content/40" />
          <span class="max-w-full truncate px-0.5 text-[10px] font-medium uppercase leading-tight text-base-content/70">
            {file_extension_label(@name)}
          </span>
          <span
            class="w-full min-w-0 truncate px-0.5 text-[10px] leading-tight text-base-content/100"
            title={@name}
          >
            {@name}
          </span>
        </div>
    <% end %>
    """
  end

  defp doc_kind_icon(:image), do: "hero-photo-mini"
  defp doc_kind_icon(:video), do: "hero-film-mini"
  defp doc_kind_icon(:pdf), do: "hero-document-text-mini"
  defp doc_kind_icon(_), do: "hero-paper-clip-mini"

  defp file_extension_label(name) when is_binary(name) do
    case Path.extname(name) |> String.trim_leading(".") |> String.downcase() do
      "" -> "file"
      ext -> ".#{ext}"
    end
  end

  defp file_extension_label(_), do: "file"
end
