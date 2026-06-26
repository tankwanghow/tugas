defmodule ArgusWeb.TodoLive.IndexHelpers do
  @moduledoc false

  use ArgusWeb, :verified_routes

  import Phoenix.Component, only: [assign: 2, assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2, stream: 4, stream_insert: 4]

  alias Argus.Authorization
  alias Argus.Todos
  alias Argus.Todos.Todo

  @statuses ~w(open completed escalated canceled all)a

  def statuses, do: Enum.map(@statuses, &{Atom.to_string(&1), status_label(&1)})

  def parse_status(status), do: Todos.parse_status(status)

  def status_label(:open), do: "Open"
  def status_label(:completed), do: "Completed"
  def status_label(:escalated), do: "Escalated"
  def status_label(:canceled), do: "Canceled"
  def status_label(:all), do: "All"

  def empty_message(:open), do: "No open todos. Add one or try another filter."
  def empty_message(:completed), do: "No completed todos yet."
  def empty_message(:escalated), do: "No escalated todos yet."
  def empty_message(:canceled), do: "No canceled todos yet."
  def empty_message(:all), do: "No todos yet. Add one to get started."

  def row_muted?(%Todo{} = todo) do
    Todo.display_status(todo) != :open
  end

  def title_strike?(%Todo{} = todo), do: Todo.completed?(todo) or Todo.canceled?(todo)

  def editable?(%Todo{} = todo), do: Todo.editable?(todo)

  def row_effect_name(row_effects, todo_id) do
    case Map.get(row_effects || %{}, todo_id) do
      nil -> nil
      effect -> Atom.to_string(effect)
    end
  end

  def row_effect_class(row_effects, todo_id) do
    case Map.get(row_effects || %{}, todo_id) do
      :created -> "todo-row--created"
      :updated -> "todo-row--updated"
      :deleted -> "todo-row--deleted"
      _ -> nil
    end
  end

  def mount_assigns(socket) do
    socket
    |> assign(:todo_form, nil)
    |> assign(:editing, nil)
    |> assign(:canceling_todo, nil)
    |> assign(:cancel_form, nil)
    |> assign(:expanded_audit_id, nil)
    |> assign(:status, :open)
    |> assign(:row_effects, %{})
    |> load_first_page()
  end

  def todo_dom_id(socket, %Todo{id: id}) do
    if socket.view == ArgusWeb.MobileLive.Todos do
      "m-todo-#{id}"
    else
      "todo-#{id}"
    end
  end

  def load_first_page(socket) do
    scope = socket.assigns.current_scope
    status = socket.assigns[:status] || :open

    case Todos.list_todos_page(scope, status: status) do
      :not_authorise ->
        socket
        |> stream(:todos, [], reset: true)
        |> assign(cursor: nil, end?: true, empty?: true, audit_by_id: %{})

      {:ok, %{rows: todos, cursor: cursor, end?: end?}} ->
        socket
        |> stream(:todos, todos, dom_id: &todo_dom_id(socket, &1), reset: true)
        |> assign(
          cursor: cursor,
          end?: end?,
          empty?: todos == [],
          audit_by_id: audit_for_todos(todos)
        )
    end
  end

  def load_more(socket) do
    scope = socket.assigns.current_scope
    status = socket.assigns[:status] || :open
    cursor = socket.assigns[:cursor]

    case Todos.list_todos_page(scope, status: status, cursor: cursor) do
      :not_authorise ->
        socket

      {:ok, %{rows: todos, cursor: new_cursor, end?: end?}} ->
        socket
        |> stream(:todos, todos, dom_id: &todo_dom_id(socket, &1), at: -1)
        |> assign(
          cursor: new_cursor,
          end?: end?,
          audit_by_id: Map.merge(socket.assigns.audit_by_id, audit_for_todos(todos))
        )
    end
  end

  defp audit_for_todos(todos) do
    Map.new(todos, fn todo -> {todo.id, Todos.list_audit_logs(todo)} end)
  end

  def open_modal(socket, template, editing, title, submit_label) do
    changeset = Todos.change_todo(template)

    socket
    |> assign(:todo_form, to_form(changeset, as: "todo"))
    |> assign(:editing, editing)
    |> assign(:modal_title, title)
    |> assign(:submit_label, submit_label)
  end

  def close_modal(socket) do
    assign(socket, todo_form: nil, editing: nil)
  end

  def close_cancel_modal(socket) do
    assign(socket, canceling_todo: nil, cancel_form: nil)
  end

  def open_cancel_modal(socket, %Todo{} = todo) do
    socket
    |> assign(:canceling_todo, todo)
    |> assign(:cancel_form, to_form(%{"note" => ""}, as: "cancel"))
  end

  def can_escalate?(scope, %Todo{} = todo) do
    Authorization.can?(scope, :create_obligation) and
      not Todo.completed?(todo) and
      Todo.active?(todo)
  end

  def has_actions?(scope, %Todo{} = todo) do
    can_escalate?(scope, todo) or editable?(todo) or Todo.deletable?(todo) or
      Todo.cancelable?(todo)
  end

  def handle_todo_action(socket, %{"action" => action})
      when action in ["", nil],
      do: {:ok, socket}

  def handle_todo_action(socket, %{"id" => id, "action" => "edit"}) do
    handle_edit(socket, id)
  end

  def handle_todo_action(socket, %{"id" => id, "action" => "delete"}) do
    handle_delete(socket, %{"id" => id})
  end

  def handle_todo_action(socket, %{"id" => id, "action" => "cancel"}) do
    handle_open_cancel(socket, %{"id" => id})
  end

  def handle_todo_action(socket, %{"id" => id, "action" => "escalate"}) do
    scope = socket.assigns.current_scope
    slug = scope.entity.slug

    path =
      if socket.view == ArgusWeb.MobileLive.Todos do
        ~p"/m/#{slug}/obligations/new?from_todo=#{id}"
      else
        ~p"/entities/#{slug}/obligations/new?from_todo=#{id}"
      end

    {:ok, push_navigate(socket, to: path)}
  end

  def handle_todo_action(socket, _params), do: {:ok, socket}

  def handle_validate(socket, %{"todo" => params}) do
    template = socket.assigns.editing || %Todo{}
    changeset = Todos.change_todo(template, params) |> Map.put(:action, :validate)

    assign(socket, :todo_form, to_form(changeset, as: "todo"))
  end

  def handle_save(socket, %{"todo" => params}) do
    scope = socket.assigns.current_scope

    result =
      case socket.assigns.editing do
        nil -> Todos.create_todo(scope, params)
        %Todo{} = todo -> Todos.update_todo(scope, todo, params)
      end

    case result do
      {:ok, todo} ->
        effect = if socket.assigns.editing, do: :updated, else: :created

        {:ok,
         socket
         |> close_modal()
         |> apply_save_effect(scope, todo, effect)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, assign(socket, :todo_form, to_form(changeset, as: "todo"))}

      :not_authorise ->
        {:not_authorise,
         socket
         |> put_flash(:error, "Not authorized.")
         |> close_modal()}

      :not_found ->
        {:not_found,
         socket
         |> put_flash(:error, "Todo not found.")
         |> close_modal()
         |> load_first_page()}
    end
  end

  def handle_edit(socket, id) do
    scope = socket.assigns.current_scope

    case Todos.get_todo(scope, id) do
      {:ok, todo} ->
        {:ok, open_modal(socket, todo, todo, "Edit todo", "Save")}

      :not_found ->
        {:not_found,
         socket
         |> put_flash(:error, "Todo not found.")
         |> load_first_page()}

      :not_authorise ->
        {:not_authorise, socket |> put_flash(:error, "Not authorized.")}
    end
  end

  def handle_toggle(socket, %{"id" => id}) do
    scope = socket.assigns.current_scope

    case Todos.get_todo(scope, id) do
      {:ok, todo} ->
        case Todos.toggle_complete(scope, todo) do
          {:ok, _todo} ->
            {:ok, load_first_page(socket)}

          :not_authorise ->
            {:not_authorise, socket |> put_flash(:error, "Not authorized.")}

          :not_found ->
            {:not_found,
             socket
             |> put_flash(:error, "Todo not found.")
             |> load_first_page()}

          {:error, _} ->
            {:error, put_flash(socket, :error, "Could not update todo.")}
        end

      :not_found ->
        {:not_found,
         socket
         |> put_flash(:error, "Todo not found.")
         |> load_first_page()}

      :not_authorise ->
        {:not_authorise, socket |> put_flash(:error, "Not authorized.")}
    end
  end

  def handle_delete(socket, %{"id" => id}) do
    scope = socket.assigns.current_scope

    case Todos.get_todo(scope, id) do
      {:ok, todo} ->
        case Todos.delete_todo(scope, todo) do
          {:ok, _} ->
            {:ok,
             socket
             |> put_row_effect(todo.id, :deleted)
             |> stream_insert_todo(todo)}

          {:error, :delete_window_expired} ->
            {:error,
             socket
             |> put_flash(:error, "Todos older than 48 hours must be canceled, not deleted.")}

          :not_authorise ->
            {:not_authorise, socket |> put_flash(:error, "Not authorized.")}

          :not_found ->
            {:not_found,
             socket
             |> put_flash(:error, "Todo not found.")
             |> load_first_page()}

          {:error, _} ->
            {:error, put_flash(socket, :error, "Could not delete todo.")}
        end

      :not_found ->
        {:not_found,
         socket
         |> put_flash(:error, "Todo not found.")
         |> load_first_page()}

      :not_authorise ->
        {:not_authorise, socket |> put_flash(:error, "Not authorized.")}
    end
  end

  def handle_open_cancel(socket, %{"id" => id}) do
    scope = socket.assigns.current_scope

    case Todos.get_todo(scope, id) do
      {:ok, todo} ->
        if Todo.cancelable?(todo) do
          {:ok, open_cancel_modal(socket, todo)}
        else
          {:error,
           socket
           |> put_flash(:error, "Recent todos must be deleted within 48 hours of creation.")}
        end

      :not_found ->
        {:not_found,
         socket
         |> put_flash(:error, "Todo not found.")
         |> load_first_page()}

      :not_authorise ->
        {:not_authorise, socket |> put_flash(:error, "Not authorized.")}
    end
  end

  def handle_submit_cancel(socket, %{"cancel" => %{"note" => note}}) do
    scope = socket.assigns.current_scope
    todo = socket.assigns.canceling_todo

    case todo && Todos.cancel_todo(scope, todo, note) do
      {:ok, _} ->
        {:ok,
         socket
         |> put_flash(:info, "Todo canceled.")
         |> close_cancel_modal()
         |> load_first_page()}

      {:error, :note_required} ->
        {:error, put_flash(socket, :error, "A cancel note is required.")}

      {:error, :not_cancelable} ->
        {:error,
         socket
         |> put_flash(:error, "Recent todos must be deleted within 48 hours of creation.")
         |> close_cancel_modal()}

      :not_authorise ->
        {:not_authorise,
         socket
         |> put_flash(:error, "Not authorized.")
         |> close_cancel_modal()}

      :not_found ->
        {:not_found,
         socket
         |> put_flash(:error, "Todo not found.")
         |> close_cancel_modal()
         |> load_first_page()}

      _ ->
        {:error,
         socket
         |> put_flash(:error, "Could not cancel todo.")
         |> close_cancel_modal()}
    end
  end

  def handle_set_status(socket, %{"status" => status}) do
    {:ok, assign(socket, :status, parse_status(status)) |> load_first_page()}
  end

  def handle_load_more(socket) do
    if socket.assigns[:end?] do
      {:ok, socket}
    else
      {:ok, load_more(socket)}
    end
  end

  def handle_finish_row_effect(socket, %{"id" => id}) do
    row_effects = Map.delete(socket.assigns.row_effects || %{}, id)

    {:ok,
     socket
     |> assign(:row_effects, row_effects)
     |> load_first_page()}
  end

  def handle_result({_status, socket}) do
    {:noreply, socket}
  end

  defp apply_save_effect(socket, scope, %Todo{} = todo, effect) do
    status = socket.assigns[:status] || :open

    if todo_visible_in_status?(todo, status) do
      socket
      |> put_row_effect(todo.id, effect)
      |> insert_todo_row(scope, todo, effect)
    else
      socket
    end
  end

  defp insert_todo_row(socket, scope, %Todo{} = todo, :created) do
    case Todos.get_todo(scope, todo.id) do
      {:ok, full_todo} ->
        socket
        |> assign(:empty?, false)
        |> merge_audit_for(full_todo)
        |> stream_insert(:todos, full_todo, dom_id: &todo_dom_id(socket, &1), at: 0)

      _ ->
        stream_insert_todo(socket, todo)
    end
  end

  defp insert_todo_row(socket, scope, %Todo{} = todo, _effect) do
    case Todos.get_todo(scope, todo.id) do
      {:ok, full_todo} -> stream_insert_todo(socket, full_todo)
      _ -> stream_insert_todo(socket, todo)
    end
  end

  defp merge_audit_for(socket, %Todo{} = todo) do
    assign(
      socket,
      :audit_by_id,
      Map.put(socket.assigns.audit_by_id, todo.id, Todos.list_audit_logs(todo))
    )
  end

  defp todo_visible_in_status?(%Todo{} = todo, :open),
    do: Todo.open?(todo) and not Todo.completed?(todo)

  defp todo_visible_in_status?(%Todo{} = todo, :completed),
    do: Todo.completed?(todo) and not Todo.escalated?(todo) and not Todo.canceled?(todo)

  defp todo_visible_in_status?(%Todo{} = todo, :escalated), do: Todo.escalated?(todo)
  defp todo_visible_in_status?(%Todo{} = todo, :canceled), do: Todo.canceled?(todo)
  defp todo_visible_in_status?(%Todo{}, :all), do: true

  defp put_row_effect(socket, todo_id, effect) do
    assign(socket, :row_effects, Map.put(socket.assigns.row_effects || %{}, todo_id, effect))
  end

  defp stream_insert_todo(socket, %Todo{} = todo) do
    stream_insert(socket, :todos, todo, dom_id: &todo_dom_id(socket, &1))
  end
end
