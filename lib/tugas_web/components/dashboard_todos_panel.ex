defmodule TugasWeb.DashboardTodosPanel do
  @moduledoc false
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: TugasWeb.Endpoint,
    router: TugasWeb.Router,
    statics: TugasWeb.static_paths()

  alias Tugas.Todos.Todo
  alias TugasWeb.TodoLive.IndexHelpers

  attr :todos, :list, required: true
  attr :completed_todos, :list, required: true
  attr :slug, :string, required: true
  attr :variant, :atom, default: :desktop
  attr :row_effects, :map, default: %{}

  def dashboard_todos_panel(assigns) do
    assigns = assign(assigns, :mobile?, assigns.variant == :mobile)

    ~H"""
    <.panel_root mobile?={@mobile?}>
      <div class="flex shrink-0 items-center gap-2 pb-2">
        <h2 class="text-lg font-semibold">Todos</h2>
        <.link navigate={todos_index_path(@variant, @slug)} class="text-sm link link-primary">
          View all →
        </.link>
      </div>

      <div class={panel_body_class(@mobile?)}>
        <div class={open_section_class(@mobile?)}>
          <ul
            :if={@todos != []}
            id="dashboard-todos-list"
            class={list_class(@mobile?)}
          >
            <.todo_row
              :for={todo <- @todos}
              todo={todo}
              slug={@slug}
              row_effects={@row_effects}
              id_prefix="dashboard-todo"
              mobile?={@mobile?}
            />
          </ul>

          <p :if={@todos == []} class={empty_class(@mobile?)}>
            No open todos.
            <.link navigate={todos_index_path(@variant, @slug)} class="link link-primary">Add one</.link>
          </p>
        </div>

        <div class={completed_section_class(@mobile?)}>
          <h3 class="mb-1 shrink-0 text-sm font-semibold text-base-content/70">
            Recently completed
          </h3>
          <ul
            :if={@completed_todos != []}
            id="dashboard-completed-todos-list"
            class={list_class(@mobile?)}
          >
            <.todo_row
              :for={todo <- @completed_todos}
              todo={todo}
              slug={@slug}
              row_effects={@row_effects}
              id_prefix="dashboard-completed-todo"
              mobile?={@mobile?}
              completed?
            />
          </ul>

          <p :if={@completed_todos == []} class={empty_class(@mobile?)}>
            No completed todos yet.
          </p>
        </div>
      </div>
    </.panel_root>
    """
  end

  attr :mobile?, :boolean, required: true
  slot :inner_block, required: true

  defp panel_root(%{mobile?: true} = assigns) do
    ~H"""
    <section
      id="dashboard-todos"
      class="h-full min-h-0 flex flex-col rounded-lg border border-base-300 bg-base-200/40 p-3"
    >
      {render_slot(@inner_block)}
    </section>
    """
  end

  defp panel_root(%{mobile?: false} = assigns) do
    ~H"""
    <aside
      id="dashboard-todos"
      class="flex h-full min-h-0 min-w-0 flex-col rounded-lg border border-base-300 bg-base-200/40 p-3"
    >
      {render_slot(@inner_block)}
    </aside>
    """
  end

  attr :todo, Todo, required: true
  attr :slug, :string, required: true
  attr :row_effects, :map, required: true
  attr :id_prefix, :string, required: true
  attr :mobile?, :boolean, default: false
  attr :completed?, :boolean, default: false

  defp todo_row(assigns) do
    ~H"""
    <li
      id={"#{@id_prefix}-#{@todo.id}"}
      phx-hook="TodoRowEffect"
      data-todo-id={@todo.id}
      data-effect={IndexHelpers.row_effect_name(@row_effects, @todo.id)}
      class={[
        "flex border border-transparent rounded",
        todo_row_layout_class(@mobile?),
        @completed? && "opacity-60",
        IndexHelpers.row_effect_class(@row_effects, @todo.id)
      ]}
    >
      <input
        id={"#{@id_prefix}-complete-#{@todo.id}"}
        type="checkbox"
        class={todo_checkbox_class(@mobile?)}
        checked={Todo.completed?(@todo)}
        phx-click="toggle_todo_complete"
        phx-value-id={@todo.id}
      />
      <span class={[
        todo_title_class(@mobile?),
        IndexHelpers.title_strike?(@todo) && "line-through text-base-content/60"
      ]}>
        {@todo.title}
      </span>
    </li>
    """
  end

  defp todo_row_layout_class(true), do: "items-center gap-3 px-2 py-3 min-h-12 bg-base-100"
  defp todo_row_layout_class(false), do: "items-start gap-2 px-1 py-1"

  defp todo_checkbox_class(true), do: "checkbox checkbox-lg shrink-0"
  defp todo_checkbox_class(false), do: "checkbox checkbox-sm mt-0.5"

  defp todo_title_class(true), do: "text-base font-medium leading-snug flex-1 min-w-0"
  defp todo_title_class(false), do: "text-sm truncate"

  defp panel_body_class(true), do: "min-h-0 flex-1 space-y-2 overflow-y-auto"
  defp panel_body_class(false), do: "flex min-h-0 flex-1 flex-col"

  defp open_section_class(true), do: ""
  defp open_section_class(false), do: "flex min-h-0 flex-[2] flex-col"

  defp completed_section_class(true), do: "border-t border-base-300 pt-2"

  defp completed_section_class(false),
    do: "mt-2 flex min-h-0 flex-[1] flex-col border-t border-base-300 pt-2"

  defp list_class(true), do: "space-y-2.5"
  defp list_class(false), do: "min-h-0 flex-1 space-y-2 overflow-y-auto"

  defp empty_class(true), do: "text-sm text-base-content/60"
  defp empty_class(false), do: "flex-1 text-sm text-base-content/60"

  defp todos_index_path(:mobile, slug), do: ~p"/m/#{slug}/todos"
  defp todos_index_path(_, slug), do: ~p"/entities/#{slug}/todos"
end
