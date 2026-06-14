defmodule ArgusWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ArgusWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar bg-base-100 border-b border-base-200 px-4 sm:px-6 lg:px-8">
      <div class="flex-1 flex items-center gap-2 min-w-0">
        <a href="/" class="flex items-center gap-2 shrink-0">
          <img src={~p"/images/logo.svg"} width="32" />
          <span class="font-semibold">Argus</span>
        </a>

        <span
          :if={entity_scope?(@current_scope)}
          class="text-sm text-base-content/70"
        >
          {@current_scope.entity.name}
        </span>
      </div>

      <div class="flex-none flex items-center gap-1">
        <nav :if={entity_scope?(@current_scope)} class="hidden md:flex items-center gap-1">
          <.link navigate={~p"/entities/#{@current_scope.entity.slug}"} class="btn btn-ghost btn-sm">
            Dashboard
          </.link>
          <.link
            navigate={~p"/entities/#{@current_scope.entity.slug}/obligations"}
            class="btn btn-ghost btn-sm"
          >
            Obligations
          </.link>
          <.link
            navigate={~p"/entities/#{@current_scope.entity.slug}/obligation-types"}
            class="btn btn-ghost btn-sm"
          >
            Types
          </.link>
          <.link
            navigate={~p"/entities/#{@current_scope.entity.slug}/members"}
            class="btn btn-ghost btn-sm"
          >
            Members
          </.link>
        </nav>

        <a
          :if={entity_scope?(@current_scope)}
          href={~p"/set-view?#{[view: "mobile", to: "/m/#{@current_scope.entity.slug}"]}"}
          class="btn btn-ghost btn-sm"
          title="Switch to mobile view"
        >
          <.icon name="hero-device-phone-mobile" class="size-5" />
        </a>

        <nav :if={!account_scope?(@current_scope)} class="flex items-center gap-1">
          <.link href={~p"/users/log-in"} class="btn btn-ghost btn-sm">Log in</.link>
          <.link href={~p"/users/register"} class="btn btn-primary btn-sm">Get started</.link>
        </nav>

        <.theme_toggle />

        <details :if={account_scope?(@current_scope)} class="dropdown dropdown-end">
          <summary class="btn btn-ghost btn-sm list-none [&::-webkit-details-marker]:hidden">
            <.icon name="hero-user-circle" class="size-5" />
          </summary>
          <ul class="dropdown-content menu bg-base-100 rounded-box shadow z-50 w-56 p-2 mt-2">
            <li class="menu-title truncate">{@current_scope.user.email}</li>
            <li><.link href={~p"/users/settings"}>Settings</.link></li>
            <li><.link href={~p"/entities?pick=1"}>All entities</.link></li>
            <li><.link href={~p"/users/log-out"} method="delete">Log out</.link></li>
          </ul>
        </details>
      </div>
    </header>

    <main class="px-4 py-6 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-5xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Minimal mobile shell for pages outside an entity context (e.g. entity picker).
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  slot :inner_block, required: true

  def mobile_simple(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <main class="px-4 py-4">
        {render_slot(@inner_block)}
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  The mobile shell — bottom-nav layout for the `/m/:entity_slug` field-work UI.
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :active, :atom, default: :home, doc: "the active bottom-nav tab"
  slot :inner_block, required: true

  def mobile_app(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100 pb-20">
      <main class="px-4 py-4">
        {render_slot(@inner_block)}
      </main>
    </div>

    <.mobile_bottom_nav active={@active} slug={@current_scope.entity.slug} />
    <.flash_group flash={@flash} />
    """
  end

  attr :active, :atom, required: true
  attr :slug, :string, required: true

  defp mobile_bottom_nav(assigns) do
    ~H"""
    <nav class="fixed bottom-0 inset-x-0 z-40 bg-base-100 border-t border-base-200 pb-[env(safe-area-inset-bottom)]">
      <div class="grid grid-cols-3">
        <.link
          navigate={~p"/m/#{@slug}"}
          class={["flex flex-col items-center gap-1 py-2 text-xs", @active == :home && "text-primary"]}
        >
          <.icon name="hero-home" class="size-6" /> Dashboard
        </.link>
        <.link
          navigate={~p"/m/#{@slug}/obligations"}
          class={[
            "flex flex-col items-center gap-1 py-2 text-xs",
            @active == :obligations && "text-primary"
          ]}
        >
          <.icon name="hero-clipboard-document-list" class="size-6" /> Tasks
        </.link>
        <label for="more-sheet" class="flex flex-col items-center gap-1 py-2 text-xs cursor-pointer">
          <.icon name="hero-ellipsis-horizontal-circle" class="size-6" /> More
        </label>
      </div>
    </nav>

    <input type="checkbox" id="more-sheet" class="modal-toggle" />
    <div class="modal modal-bottom" role="dialog">
      <div class="modal-box">
        <h3 class="font-bold text-lg">More</h3>
        <ul class="menu mt-2">
          <li>
            <a href={~p"/set-view?#{[view: "desktop", to: "/entities/#{@slug}"]}"}>
              <.icon name="hero-computer-desktop" class="size-5" /> Switch to desktop
            </a>
          </li>
          <li>
            <.link href={~p"/m/entities?pick=1"}>
              <.icon name="hero-building-office-2" class="size-5" /> All entities
            </.link>
          </li>
          <li>
            <.link navigate={~p"/users/settings"}>
              <.icon name="hero-cog-6-tooth" class="size-5" /> Settings
            </.link>
          </li>
          <li>
            <.link href={~p"/users/log-out"} method="delete">
              <.icon name="hero-arrow-right-start-on-rectangle" class="size-5" /> Log out
            </.link>
          </li>
        </ul>
        <div class="mt-4 flex justify-center">
          <.theme_toggle />
        </div>
      </div>
      <label class="modal-backdrop" for="more-sheet">Close</label>
    </div>
    """
  end

  defp entity_scope?(%{entity: %{} = _entity}), do: true
  defp entity_scope?(_), do: false

  defp account_scope?(%{user: %{} = _user}), do: true
  defp account_scope?(_), do: false

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
