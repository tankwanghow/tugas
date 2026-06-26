defmodule ArgusWeb.TodoBadge do
  @moduledoc """
  Status badge for todo rows — completed, escalated, or canceled.
  Open todos show no badge.
  """
  use Phoenix.Component

  alias Argus.Todos.Todo

  attr :todo, Todo, required: true

  def todo_badge(assigns) do
    status = Todo.display_status(assigns.todo)

    assigns =
      assigns
      |> assign(:status, status)
      |> assign(:label, badge_label(status))

    ~H"""
    <span
      :if={@status != :open}
      id={"todo-badge-#{@todo.id}"}
      class={["badge", badge_class(@status)]}
      data-todo-status={@status}
    >
      {@label}
    </span>
    """
  end

  defp badge_label(:completed), do: "Completed"
  defp badge_label(:escalated), do: "Escalated"
  defp badge_label(:canceled), do: "Canceled"
  defp badge_label(:open), do: nil

  defp badge_class(:completed), do: "badge-success badge-soft"
  defp badge_class(:escalated), do: "badge-info badge-soft"
  defp badge_class(:canceled), do: "badge-ghost"
  defp badge_class(:open), do: "badge-ghost"
end
