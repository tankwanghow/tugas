defmodule ArgusWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: ArgusWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset">
      <label for={@id}>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  A single-line text input with a live "characters left" counter (Twitter-style).

  Enforces `maxlength` in the browser and shows the remaining count, which
  updates instantly client-side via a colocated hook (no server round-trip).
  Pair with a `validate_length/3` on the changeset for the authoritative limit.
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, default: nil
  attr :max, :integer, default: 30
  attr :rest, :global, include: ~w(required placeholder autocomplete autofocus)

  def char_count_input(assigns) do
    ~H"""
    <div>
      <p
        id={"#{@field.id}-count"}
        class="-mb-6 mr-2 text-right text-xs text-base-content/100"
        aria-live="polite"
      >
        {@max}
      </p>
      <.input
        field={@field}
        type="text"
        label={@label}
        maxlength={@max}
        phx-hook=".CharCount"
        data-counter={"#{@field.id}-count"}
        {@rest}
      />
      <script :type={Phoenix.LiveView.ColocatedHook} name=".CharCount">
        export default {
          mounted() {
            this._u = () => this.update()
            this.el.addEventListener("input", this._u)
            this.update()
          },
          updated() { this.update() },
          destroyed() { this.el.removeEventListener("input", this._u) },
          update() {
            const max = parseInt(this.el.getAttribute("maxlength") || "0", 10)
            const left = max - this.el.value.length
            const c = document.getElementById(this.el.dataset.counter)
            if (!c) return
            c.textContent = left
            c.classList.toggle("text-error", left <= 0)
            c.classList.toggle("text-warning", left > 0 && left <= 5)
          }
        }
      </script>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex flex-wrap items-start justify-between gap-2", "pb-3"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  Renders a link to an uploaded document.

  Renders a leading file-type icon (photo / film / document-text / paperclip)
  followed by the filename link. Images, videos and PDFs open in the shared
  in-page preview modal (handled client-side in `app.js`, which reads the
  `data-doc-*` attributes); other file types fall back to opening/downloading in
  a new tab. The preview kind and the icon are both classified server-side from
  the filename via `file_kind/1`, so they stay in sync. Requires
  `doc_preview_modal/1` to be present once on the page.
  """
  attr :href, :string, required: true
  attr :name, :string, required: true
  attr :class, :any, default: nil
  attr :icon_class, :any, default: "size-3.5 text-base-content/40 shrink-0"
  attr :rest, :global

  def doc_link(assigns) do
    assigns =
      assign(assigns, :kind, ArgusWeb.ObligationLive.DocumentHelpers.file_kind(assigns.name))

    ~H"""
    <.icon name={doc_kind_icon(@kind)} class={@icon_class} />
    <a
      href={@href}
      target="_blank"
      rel="noopener"
      data-doc-preview
      data-doc-kind={@kind}
      data-doc-name={@name}
      class={@class}
      {@rest}
    >{@name}</a>
    """
  end

  defp doc_kind_icon(:image), do: "hero-photo-mini"
  defp doc_kind_icon(:video), do: "hero-film-mini"
  defp doc_kind_icon(:pdf), do: "hero-document-text-mini"
  defp doc_kind_icon(_), do: "hero-paper-clip-mini"

  @doc """
  Renders the shared, page-level document preview modal that `doc_link/1` opens.

  Populated client-side (`#doc-preview-name`, `#doc-preview-download`,
  `#doc-preview-body`); render it once per layout shell.
  """
  def doc_preview_modal(assigns) do
    ~H"""
    <dialog id="doc-preview-modal" class="modal">
      <div class="modal-box w-11/12 max-w-4xl p-4">
        <div class="mb-3 flex items-center justify-between gap-2">
          <h3 id="doc-preview-name" class="min-w-0 truncate font-semibold"></h3>
          <div class="flex shrink-0 items-center gap-2">
            <a id="doc-preview-download" href="#" download class="btn btn-sm btn-primary">
              <.icon name="hero-arrow-down-tray-mini" class="size-4" />
              <span class="hidden sm:inline">Download</span>
            </a>
            <form id="doc-preview-close" method="dialog">
              <button class="btn btn-sm btn-circle btn-ghost" aria-label="Close">✕</button>
            </form>
          </div>
        </div>
        <div
          id="doc-preview-body"
          class="max-h-[75vh] min-h-[40vh] overflow-auto text-center"
        >
        </div>
      </div>
      <form id="doc-preview-backdrop" method="dialog" class="modal-backdrop">
        <button aria-label="Close">close</button>
      </form>
    </dialog>
    """
  end

  @doc """
  How a user is represented in the UI — their username when set, else email.
  Delegates to `Argus.Accounts.User.display_name/1`; use this in any template
  that would otherwise render a user's raw email.
  """
  def user_label(%Argus.Accounts.User{} = user), do: Argus.Accounts.User.display_name(user)

  @doc """
  Formats a `Date` (a plain calendar date — no time zone) for display, e.g. `15 Jan 2026`.

  `due_by` and other bare dates carry no instant, so they are never shifted; only stored
  `DateTime`s (see `format_datetime/3`) are rendered in the entity's zone.
  """
  def format_date(date, format \\ :default)
  def format_date(nil, _format), do: "—"
  def format_date(%Date{} = date, :short), do: Calendar.strftime(date, "%Y-%m-%d")
  def format_date(%Date{} = date, _format), do: Calendar.strftime(date, "%d %b %Y")

  @doc """
  Formats a stored (UTC) `DateTime` for display **in the entity `timezone`**, e.g.
  `15 Jan 2026, 14:30` (`:short` → `2026-01-15 14:30`). Falls back to the original instant
  if the zone can't be resolved.
  """
  def format_datetime(dt, timezone, format \\ :default)
  def format_datetime(nil, _timezone, _format), do: ""

  def format_datetime(%DateTime{} = dt, timezone, :short),
    do: dt |> in_zone(timezone) |> Calendar.strftime("%Y-%m-%d %H:%M")

  def format_datetime(%DateTime{} = dt, timezone, _format),
    do: dt |> in_zone(timezone) |> Calendar.strftime("%d %b %Y, %H:%M")

  @doc """
  Formats a stored (UTC) `DateTime` as a **date in the entity `timezone`** (e.g. a
  completion day or invite expiry). Shifts the instant before taking the date so it lands
  on the correct local day near midnight.
  """
  def format_zoned_date(dt, timezone, format \\ :default)
  def format_zoned_date(nil, _timezone, _format), do: nil

  def format_zoned_date(%DateTime{} = dt, timezone, format),
    do: dt |> in_zone(timezone) |> DateTime.to_date() |> format_date(format)

  @doc """
  Shifts a UTC `DateTime` into `timezone`, falling back to the original instant when the
  zone is missing/invalid. Public so non-CoreComponents render modules can reuse it.
  """
  def in_zone(%DateTime{} = dt, timezone) when is_binary(timezone) and timezone != "" do
    case DateTime.shift_zone(dt, timezone) do
      {:ok, shifted} -> shifted
      {:error, _} -> dt
    end
  end

  def in_zone(%DateTime{} = dt, _timezone), do: dt

  @doc """
  A human-friendly relative label for a due date against `today`,
  e.g. `due today`, `due in 3 days`, `2 days overdue`.
  """
  def due_label(%Date{} = due_by, %Date{} = today) do
    case Date.diff(due_by, today) do
      0 -> "due today"
      1 -> "due tomorrow"
      n when n > 0 -> "due in #{n} days"
      -1 -> "1 day overdue"
      n -> "#{abs(n)} days overdue"
    end
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(ArgusWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(ArgusWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
