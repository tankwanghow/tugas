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
  attr :row_effects, :map, default: %{}

  def dashboard_todos_panel(assigns) do
    ~H"""
    <aside
      id="dashboard-todos"
      class="flex h-full min-h-0 flex-1 flex-col rounded-lg border border-base-300 bg-base-200/40 p-3"
    >
      <div class="flex shrink-0 items-center gap-2 pb-2">
        <h2 class="text-lg font-semibold">Todos</h2>
        <.link navigate={~p"/entities/#{@slug}/todos"} class="text-sm link link-primary">
          View all →
        </.link>
      </div>

      <div class="flex min-h-0 flex-1 flex-col">
        <div class="flex min-h-0 flex-[2] flex-col">
          <ul
            :if={@todos != []}
            id="dashboard-todos-list"
            class="min-h-0 flex-1 space-y-2 overflow-y-auto"
          >
            <.todo_row
              :for={todo <- @todos}
              todo={todo}
              slug={@slug}
              row_effects={@row_effects}
              id_prefix="dashboard-todo"
            />
          </ul>

          <p :if={@todos == []} class="flex-1 text-sm text-base-content/60">
            No open todos.
            <.link navigate={~p"/entities/#{@slug}/todos"} class="link link-primary">Add one</.link>
          </p>
        </div>

        <div class="mt-2 flex min-h-0 flex-[1] flex-col border-t border-base-300 pt-2">
          <h3 class="mb-1 shrink-0 text-sm font-semibold text-base-content/70">
            Recently completed
          </h3>
          <ul
            :if={@completed_todos != []}
            id="dashboard-completed-todos-list"
            class="min-h-0 flex-1 space-y-2 overflow-y-auto"
          >
            <.todo_row
              :for={todo <- @completed_todos}
              todo={todo}
              slug={@slug}
              row_effects={@row_effects}
              id_prefix="dashboard-completed-todo"
              completed?
            />
          </ul>

          <p :if={@completed_todos == []} class="flex-1 text-sm text-base-content/60">
            No completed todos yet.
          </p>
        </div>
      </div>
    </aside>
    """
  end

  attr :todo, Todo, required: true
  attr :slug, :string, required: true
  attr :row_effects, :map, required: true
  attr :id_prefix, :string, required: true
  attr :completed?, :boolean, default: false

  defp todo_row(assigns) do
    ~H"""
    <li
      id={"#{@id_prefix}-#{@todo.id}"}
      phx-hook="TodoRowEffect"
      data-todo-id={@todo.id}
      data-effect={IndexHelpers.row_effect_name(@row_effects, @todo.id)}
      class={[
        "flex items-start gap-2 px-1 py-1 border border-transparent rounded",
        @completed? && "opacity-60",
        IndexHelpers.row_effect_class(@row_effects, @todo.id)
      ]}
    >
      <input
        id={"#{@id_prefix}-complete-#{@todo.id}"}
        type="checkbox"
        class="checkbox checkbox-sm mt-0.5"
        checked={Todo.completed?(@todo)}
        phx-click="toggle_todo_complete"
        phx-value-id={@todo.id}
      />
      <span class={[
        "text-sm truncate",
        IndexHelpers.title_strike?(@todo) && "line-through text-base-content/60"
      ]}>
        {@todo.title}
      </span>
    </li>
    """
  end
end