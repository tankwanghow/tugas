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
    <div
      id="argus-shell"
      phx-window-keydown="close_modal_on_escape"
      phx-key="Escape"
      class="argus-app min-h-screen flex flex-col"
    >
      <.doc_preview_modal />
      <header class="navbar px-4 sm:px-6 lg:px-8 border-b border-base-300">
        <div class="flex-1">
          <.link
            navigate={entity_dashboard_nav(@current_scope)}
            class="flex items-center gap-2 font-bold text-lg"
          >
            <span>Argus</span>
            <span
              :if={entity_scope?(@current_scope)}
              class="text-base-content/60"
            >
              {@current_scope.entity.name}<span class="text-sm ml-2 font-mono">({@current_scope.entity.slug})</span>
            </span>
          </.link>
        </div>
        <div class="flex-none">
          <ul class="flex items-center gap-2">
            <%= if account_scope?(@current_scope) do %>
              <li :if={entity_scope?(@current_scope)}>
                <a
                  href={ArgusWeb.Paths.view_mode("mobile", "/m/#{@current_scope.entity.slug}")}
                  class="btn btn-ghost btn-sm"
                  title="Mobile view"
                >
                  <.icon name="hero-device-phone-mobile-micro" class="size-4" />
                  <span class="hidden sm:inline ml-1">Mobile</span>
                </a>
              </li>
              <li>
                <.user_dropdown current_scope={@current_scope} />
              </li>
            <% else %>
              <li><.language_switcher current_scope={@current_scope} anonymous={true} /></li>
              <li><.theme_toggle /></li>
              <li>
                <.link navigate={~p"/users/log-in"} class="btn btn-ghost btn-sm">
                  Log in
                </.link>
              </li>
              <li>
                <.link navigate={~p"/users/register"} class="btn btn-primary btn-sm">
                  Get started
                </.link>
              </li>
            <% end %>
          </ul>
        </div>
      </header>

      <.entity_nav :if={entity_scope?(@current_scope)} current_scope={@current_scope} />

      <main class="flex-1 px-4 py-5 sm:px-6 lg:px-8">
        <div class="mx-auto max-w-4xl space-y-3">
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :current_scope, :map, required: true

  defp entity_nav(assigns) do
    ~H"""
    <nav class="border-b border-base-300 bg-base-200/50 px-4 sm:px-6 lg:px-8 overflow-visible">
      <div class="mx-auto max-w-4xl flex items-center justify-center gap-1 flex-wrap text-sm overflow-visible">
        <.entity_nav_link
          href={~p"/entities/#{@current_scope.entity.slug}"}
          label="💼 Duties"
        />
        <.entity_nav_link
          href={~p"/entities/#{@current_scope.entity.slug}/todos"}
          label="📑 Todos"
        />
        <.entity_nav_link
          href={~p"/entities/#{@current_scope.entity.slug}/obligation-types"}
          label="🏷️ Types"
        />
      </div>
    </nav>
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, default: nil
  attr :label, :string, required: true

  defp entity_nav_link(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class="flex items-center gap-1.5 px-3 py-2.5 rounded-md text-base-content/70 hover:text-base-content hover:bg-base-300/50 transition-colors whitespace-nowrap"
    >
      <.icon :if={@icon} name={@icon} class="size-4" />
      {@label}
    </.link>
    """
  end

  @doc "Language picker. Renders for logged-in users, or when `anonymous: true`."
  attr :current_scope, :map, default: nil
  attr :anonymous, :boolean, default: false

  def language_switcher(assigns) do
    assigns = assign(assigns, :current, Gettext.get_locale(ArgusWeb.Gettext))

    ~H"""
    <div
      :if={@anonymous || (@current_scope && @current_scope.user)}
      class="dropdown dropdown-end"
    >
      <div tabindex="0" role="button" class="btn btn-ghost btn-sm gap-1" title="Language">
        <.icon name="hero-language-micro" class="size-4" />
        <span class="hidden sm:inline">{language_label(@current)}</span>
      </div>
      <ul tabindex="0" class="dropdown-content menu bg-base-100 rounded-box z-50 w-44 p-2 shadow">
        <li :for={{code, label} <- language_options()}>
          <.link href={~p"/locale/#{code}"} class={@current == code && "menu-active"}>
            {label}
          </.link>
        </li>
      </ul>
    </div>
    """
  end

  defp language_options, do: [{"en", "English"}, {"ms", "Bahasa Malaysia"}, {"zh", "中文"}]

  defp language_label(code) do
    {_, label} = Enum.find(language_options(), {code, code}, fn {c, _} -> c == code end)
    label
  end

  defp display_name(%{username: u}) when is_binary(u) and u != "", do: u
  defp display_name(%{email: e}), do: e || "?"

  attr :current_scope, :map, required: true

  defp user_dropdown(assigns) do
    assigns = assign(assigns, :current_locale, Gettext.get_locale(ArgusWeb.Gettext))

    ~H"""
    <div id="user-dropdown" class="dropdown dropdown-end">
      <div
        tabindex="0"
        role="button"
        class="flex items-center gap-2 rounded-full border border-primary/30 bg-primary/10 pl-1 pr-3 py-1 cursor-pointer hover:bg-primary/20 transition-colors"
      >
        <div class="size-7 rounded-full bg-primary flex items-center justify-center text-primary-content text-xs font-bold flex-shrink-0 select-none">
          {String.upcase(String.first(display_name(@current_scope.user)))}
        </div>
        <span class="hidden sm:block text-sm font-medium truncate max-w-[160px]">
          {display_name(@current_scope.user)}
        </span>
        <.icon name="hero-chevron-down-micro" class="size-3 text-base-content/50" />
      </div>

      <div
        tabindex="0"
        class="dropdown-content z-50 mt-2 w-60 rounded-xl border border-base-300 bg-base-100 shadow-xl"
      >
        <div class="px-4 py-3 border-b border-base-200 bg-base-200/40">
          <div class="flex items-center gap-3">
            <div class="size-9 rounded-full bg-primary flex items-center justify-center text-primary-content text-sm font-bold flex-shrink-0 select-none">
              {String.upcase(String.first(display_name(@current_scope.user)))}
            </div>
            <div class="min-w-0">
              <div class="font-semibold text-sm truncate">{display_name(@current_scope.user)}</div>
              <div
                :if={entity_scope?(@current_scope)}
                class="text-xs text-base-content/50 font-mono truncate"
              >
                {@current_scope.entity.slug}
              </div>
            </div>
          </div>
        </div>

        <div class="py-1">
          <p class="px-3 pt-2 pb-1 text-[10px] uppercase tracking-widest text-base-content/40 font-semibold">
            Preferences
          </p>
          <div class="flex items-center justify-between px-3 py-2">
            <span class="flex items-center gap-2 text-sm">
              <.icon name="hero-language-micro" class="size-4 text-base-content/50" /> Language
            </span>
            <div class="flex gap-0.5">
              <.link
                :for={{code, _label} <- language_options()}
                href={~p"/locale/#{code}"}
                class={[
                  "px-1.5 py-0.5 rounded text-xs font-mono",
                  @current_locale == code &&
                    "bg-primary text-primary-content font-semibold",
                  @current_locale != code &&
                    "text-base-content/50 hover:text-base-content hover:bg-base-200"
                ]}
              >
                {String.upcase(code)}
              </.link>
            </div>
          </div>
          <div class="flex items-center justify-between px-3 py-2">
            <span class="flex items-center gap-2 text-sm">
              <.icon name="hero-swatch-micro" class="size-4 text-base-content/50" /> Theme
            </span>
            <.theme_toggle />
          </div>
        </div>

        <div class="border-t border-base-200 py-1">
          <p class="px-3 pt-2 pb-1 text-[10px] uppercase tracking-widest text-base-content/40 font-semibold">
            Entity
          </p>
          <.link
            navigate={~p"/entities?pick=1"}
            class="flex items-center gap-2 px-3 py-2 text-sm hover:bg-base-200 rounded transition-colors"
          >
            <.icon name="hero-building-office-2-micro" class="size-4 text-base-content/50" />
            All entities
          </.link>
          <.link
            :if={entity_scope?(@current_scope)}
            navigate={~p"/entities/#{@current_scope.entity.slug}/members"}
            class="flex items-center gap-2 px-3 py-2 text-sm hover:bg-base-200 rounded transition-colors"
          >
            <.icon name="hero-users-micro" class="size-4 text-base-content/50" /> Members
          </.link>
          <.link
            :if={
              entity_scope?(@current_scope) &&
                Argus.Authorization.can?(@current_scope, :view_todos)
            }
            id="todo-team-log-nav-link"
            navigate={~p"/entities/#{@current_scope.entity.slug}/todos/team-log"}
            class="flex items-center gap-2 px-3 py-2 text-sm hover:bg-base-200 rounded transition-colors"
          >
            <.icon name="hero-clipboard-document-list-micro" class="size-4 text-base-content/50" />
            Todo team log
          </.link>
        </div>

        <div class="border-t border-base-200 py-1">
          <p class="px-3 pt-2 pb-1 text-[10px] uppercase tracking-widest text-base-content/40 font-semibold">
            Account
          </p>
          <.link
            navigate={~p"/users/settings"}
            class="flex items-center gap-2 px-3 py-2 text-sm hover:bg-base-200 rounded transition-colors"
          >
            <.icon name="hero-user-circle-micro" class="size-4 text-base-content/50" />
            Account settings
          </.link>
          <.link
            href={~p"/users/log-out"}
            method="delete"
            class="flex items-center gap-2 px-3 py-2 text-sm text-error hover:bg-error/10 rounded transition-colors"
          >
            <.icon name="hero-power" class="size-4" /> Log out
          </.link>
        </div>
      </div>
    </div>
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
  Centered mobile shell for flows outside entity context (e.g. invitation acceptance).
  """
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def mobile_standalone(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
    <div class="min-h-screen bg-base-200 flex flex-col items-center justify-center p-6 gap-6">
      <div class="text-2xl font-bold tracking-tight">Argus</div>
      {render_slot(@inner_block)}
    </div>
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
    <div
      id="argus-shell"
      phx-window-keydown="close_modal_on_escape"
      phx-key="Escape"
      class="min-h-screen bg-base-100 pb-20"
    >
      <.doc_preview_modal />
      {render_slot(@inner_block)}
    </div>

    <.mobile_bottom_nav active={@active} current_scope={@current_scope} />
    <.mobile_more_sheet current_scope={@current_scope} />
    <.flash_group flash={@flash} />
    """
  end

  attr :active, :atom, required: true
  attr :current_scope, :map, required: true

  defp mobile_bottom_nav(assigns) do
    ~H"""
    <nav class="fixed bottom-0 inset-x-0 z-30 bg-base-100 border-t border-base-300 pb-[env(safe-area-inset-bottom)]">
      <ul class="grid grid-cols-5">
        <li>
          <.link
            id="m-new-todo-nav-link"
            navigate={~p"/m/#{@current_scope.entity.slug}/todos/new"}
            class={[
              "flex flex-col items-center gap-1 py-3 active:bg-base-200",
              @active == :new_todo && "text-primary",
              @active != :new_todo && "text-base-content/60"
            ]}
          >
            <span class="text-2xl">✚</span>
            <span class="text-sm leading-tight text-center">Todo</span>
          </.link>
        </li>
        <li>
          <.link
            id="m-todos-nav-link"
            navigate={~p"/m/#{@current_scope.entity.slug}/todos"}
            class={[
              "flex flex-col items-center gap-1 py-3 active:bg-base-200",
              @active == :todos && "text-primary",
              @active != :todos && "text-base-content/60"
            ]}
          >
            <span class="text-2xl">📑</span>
            <span class="text-sm leading-tight text-center">Todos</span>
          </.link>
        </li>
        <li>
          <.link
            id="m-new-duties-nav-link"
            navigate={~p"/m/#{@current_scope.entity.slug}/obligations/new"}
            class={[
              "flex flex-col items-center gap-1 py-3 active:bg-base-200",
              @active == :new_duty && "text-primary",
              @active != :new_duty && "text-base-content/60"
            ]}
          >
            <span class="text-2xl">✚</span>
            <span class="text-sm leading-tight text-center">Duty</span>
          </.link>
        </li>
        <li>
          <.link
            id="m-duties-nav-link"
            navigate={~p"/m/#{@current_scope.entity.slug}"}
            class={[
              "flex flex-col items-center gap-1 py-3 active:bg-base-200",
              @active == :duties && "text-primary",
              @active != :duties && "text-base-content/60"
            ]}
          >
            <span class="text-2xl">💼</span>
            <span class="text-sm leading-tight text-center">Duties</span>
          </.link>
        </li>
        <li>
          <button
            type="button"
            phx-click={JS.show(to: "#mobile-more-sheet", display: "flex")}
            class={[
              "w-full flex flex-col items-center gap-1 py-3 active:bg-base-200",
              @active == :more && "text-primary",
              @active != :more && "text-base-content/60"
            ]}
          >
            <span class="text-2xl">☰</span>
            <span class="text-sm leading-tight text-center">More</span>
          </button>
        </li>
      </ul>
    </nav>
    """
  end

  defp mobile_more_sheet(assigns) do
    ~H"""
    <div id="mobile-more-sheet" class="hidden fixed inset-0 z-40 flex items-end">
      <div class="absolute inset-0 bg-black/40" phx-click={JS.hide(to: "#mobile-more-sheet")}></div>
      <div class="relative w-full bg-base-100 rounded-t-2xl pb-[env(safe-area-inset-bottom)]">
        <div class="flex justify-center pt-2 pb-1">
          <div class="w-10 h-1 rounded-full bg-base-300"></div>
        </div>
        <div :if={@current_scope && @current_scope.user} class="px-4 py-2 border-b border-base-200">
          <div class="text-sm font-semibold">{user_label(@current_scope.user)}</div>
          <div :if={@current_scope.entity} class="text-xs text-base-content/60">
            {@current_scope.entity.name} <span class="font-mono">({@current_scope.entity.slug})</span>
          </div>
        </div>
        <ul class="divide-y divide-base-200">
          <li class="flex items-center justify-between gap-3 px-4 py-3">
            <span class="flex items-center gap-3">
              <.icon name="hero-swatch" class="size-5 text-base-content/60" />
              <span>Theme</span>
            </span>
            <.theme_toggle />
          </li>
          <li :if={
            @current_scope && @current_scope.entity &&
              Argus.Authorization.can?(@current_scope, :manage_entity)
          }>
            <.link
              id="m-more-members-link"
              navigate={~p"/m/#{@current_scope.entity.slug}/members"}
              class="flex items-center gap-3 px-4 py-4 active:bg-base-200"
            >
              <.icon name="hero-users" class="size-5 text-base-content/60" />
              <span>Members</span>
            </.link>
          </li>
          <li :if={
            @current_scope && @current_scope.entity &&
              Argus.Authorization.can?(@current_scope, :manage_entity)
          }>
            <.link
              navigate={~p"/m/#{@current_scope.entity.slug}/invite-session/member"}
              class="flex items-center gap-3 px-4 py-4 active:bg-base-200"
            >
              <.icon name="hero-user-plus" class="size-5 text-base-content/60" />
              <span>Invite session</span>
            </.link>
          </li>
          <li :if={
            @current_scope && @current_scope.entity &&
              Argus.Authorization.can?(@current_scope, :manage_types)
          }>
            <.link
              id="m-more-types-link"
              navigate={~p"/m/#{@current_scope.entity.slug}/obligation-types"}
              class="flex items-center gap-3 px-4 py-4 active:bg-base-200"
            >
              <.icon name="hero-tag" class="size-5 text-base-content/60" />
              <span>Types</span>
            </.link>
          </li>
          <li :if={
            @current_scope && @current_scope.entity &&
              Argus.Authorization.can?(@current_scope, :view_todos)
          }>
            <.link
              id="m-more-todo-team-log-link"
              navigate={~p"/m/#{@current_scope.entity.slug}/todos/team-log"}
              class="flex items-center gap-3 px-4 py-4 active:bg-base-200"
            >
              <.icon name="hero-clipboard-document-list" class="size-5 text-base-content/60" />
              <span>Todo team log</span>
            </.link>
          </li>
          <li :if={@current_scope && @current_scope.entity}>
            <a
              href={ArgusWeb.Paths.view_mode("desktop", "/entities/#{@current_scope.entity.slug}")}
              class="flex items-center gap-3 px-4 py-4 active:bg-base-200"
            >
              <.icon name="hero-computer-desktop" class="size-5 text-base-content/60" />
              <span>Open desktop view</span>
            </a>
          </li>
          <li>
            <.link
              href={~p"/entities?pick=1"}
              class="flex items-center gap-3 px-4 py-4 active:bg-base-200"
            >
              <.icon name="hero-arrows-right-left" class="size-5 text-base-content/60" />
              <span>Switch entity</span>
            </.link>
          </li>
          <li>
            <.link
              navigate={~p"/users/settings"}
              class="flex items-center gap-3 px-4 py-4 active:bg-base-200"
            >
              <.icon name="hero-cog-6-tooth" class="size-5 text-base-content/60" />
              <span>Account settings</span>
            </.link>
          </li>
          <li>
            <.link
              href={~p"/users/log-out"}
              method="delete"
              class="flex items-center gap-3 px-4 py-4 active:bg-error/10 text-error"
            >
              <.icon name="hero-arrow-left-start-on-rectangle" class="size-5" />
              <span>Log out</span>
            </.link>
          </li>
        </ul>
        <button
          type="button"
          phx-click={JS.hide(to: "#mobile-more-sheet")}
          class="w-full py-3 text-sm text-base-content/60 border-t border-base-200"
        >
          Close
        </button>
      </div>
    </div>
    """
  end

  defp entity_dashboard_nav(%{entity: %{slug: slug}}), do: ~p"/entities/#{slug}"
  defp entity_dashboard_nav(_), do: ~p"/"

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
  attr :compact, :boolean, default: false

  def theme_toggle(assigns) do
    ~H"""
    <div class={[
      "relative flex flex-row items-center border border-base-300 bg-base-200 rounded-full",
      if(@compact, do: "scale-90", else: "")
    ]}>
      <div class="absolute w-1/3 h-full rounded-full border border-base-300 bg-base-100 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-1.5 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-3.5 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-1.5 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-3.5 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-1.5 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-3.5 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
