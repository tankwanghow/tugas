defmodule ArgusWeb.TodoActionsMenu do
  @moduledoc """
  Per-todo action picker — escalate, edit, delete, and cancel in a select box.
  """
  use Phoenix.Component

  alias ArgusWeb.TodoLive.IndexHelpers
  alias Argus.Todos.Todo

  attr :todo, Todo, required: true
  attr :current_scope, :map, required: true
  attr :mobile?, :boolean, default: false

  def todo_actions_menu(assigns) do
    assigns =
      assigns
      |> assign(:has_actions?, IndexHelpers.has_actions?(assigns.current_scope, assigns.todo))
      |> assign(:id_prefix, if(assigns.mobile?, do: "m-todo", else: "todo"))
      |> assign(:options, action_options(assigns))

    ~H"""
    <div
      :if={@has_actions?}
      id={"#{@id_prefix}-actions-#{@todo.id}"}
      class="flex shrink-0 items-center gap-1"
    >
      <select
        id={"#{@id_prefix}-actions-select-#{@todo.id}"}
        name="action"
        phx-hook="TodoActionSelect"
        data-todo-id={@todo.id}
        class="select select-bordered w-16 min-w-0"
        aria-label="Todo actions"
      >
        <option value="">🛠️</option>
        <option
          :for={option <- @options}
          id={option.id}
          value={option.value}
          data-test-action={option.value}
        >
          {option.label}
        </option>
      </select>
    </div>
    """
  end

  defp action_options(assigns) do
    prefix = if(assigns.mobile?, do: "m-todo", else: "todo")
    todo = assigns.todo
    scope = assigns.current_scope

    []
    |> maybe_option(
      IndexHelpers.can_escalate?(scope, todo),
      "#{prefix}-escalate-#{todo.id}",
      "escalate",
      "💼 Duty"
    )
    |> maybe_option(
      IndexHelpers.editable?(todo),
      "#{prefix}-edit-#{todo.id}",
      "edit",
      "📝 Edit"
    )
    |> maybe_option(
      Todo.deletable?(todo),
      "#{prefix}-delete-#{todo.id}",
      "delete",
      "❌ Delete"
    )
    |> maybe_option(
      Todo.cancelable?(todo),
      "#{prefix}-cancel-#{todo.id}",
      "cancel",
      "🚫 Cancel"
    )
  end

  defp maybe_option(options, true, id, value, label),
    do: options ++ [%{id: id, value: value, label: label}]

  defp maybe_option(options, false, _id, _value, _label), do: options
end
