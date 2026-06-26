defmodule ArgusWeb.TodoActionsMenu do
  @moduledoc """
  Per-todo action picker — escalate, edit, delete, and cancel.

  Desktop renders the actions as an always-visible inline button row. Mobile hides the
  same buttons and reveals them (full width) on a press-and-hold of the todo `<li>`
  (the `TodoRowEffect` hook's long-press branch toggles the row's
  `[data-todo-actions-menu]`).
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

    if assigns.mobile? do
      mobile_menu(assigns)
    else
      desktop_menu(assigns)
    end
  end

  defp desktop_menu(assigns) do
    ~H"""
    <div
      :if={@has_actions?}
      id={"#{@id_prefix}-actions-#{@todo.id}"}
      class="flex shrink-0 flex-wrap items-center gap-1"
    >
      <button
        :for={option <- @options}
        type="button"
        id={option.id}
        phx-click="todo_action"
        phx-value-id={@todo.id}
        phx-value-action={option.value}
        data-confirm={option.confirm}
        data-test-action={option.value}
        class="btn btn-sm"
      >
        {option.label}
      </button>
    </div>
    """
  end

  # Hidden by default; the row's `TodoRowEffect` long-press branch flips `display` to reveal it.
  defp mobile_menu(assigns) do
    ~H"""
    <div
      :if={@has_actions?}
      id={"#{@id_prefix}-actions-#{@todo.id}"}
      style="display:none"
      class="mt-2 w-full gap-2"
      data-todo-actions-menu
    >
      <button
        :for={option <- @options}
        type="button"
        id={option.id}
        phx-click="todo_action"
        phx-value-id={@todo.id}
        phx-value-action={option.value}
        data-confirm={option.confirm}
        data-test-action={option.value}
        class="btn btn-lg flex-1 px-2"
      >
        {option.label}
      </button>
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
      "❌ Delete",
      "Delete this todo?"
    )
    |> maybe_option(
      Todo.cancelable?(todo),
      "#{prefix}-cancel-#{todo.id}",
      "cancel",
      "🚫 Cancel"
    )
  end

  defp maybe_option(options, enabled?, id, value, label, confirm \\ nil)

  defp maybe_option(options, true, id, value, label, confirm),
    do: options ++ [%{id: id, value: value, label: label, confirm: confirm}]

  defp maybe_option(options, false, _id, _value, _label, _confirm), do: options
end
