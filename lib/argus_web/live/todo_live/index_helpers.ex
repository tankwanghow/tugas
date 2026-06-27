defmodule ArgusWeb.TodoLive.IndexHelpers do
  @moduledoc false

  use ArgusWeb, :verified_routes

  import Phoenix.Component, only: [assign: 2, assign: 3, to_form: 2]

  import Phoenix.LiveView,
    only: [
      connected?: 1,
      put_flash: 3,
      push_event: 3,
      push_navigate: 2,
      stream: 4,
      stream_insert: 4
    ]

  alias Argus.Authorization
  alias Argus.Todos
  alias Argus.Todos.Todo

  # The index shows a single unified list (every lifecycle) ordered open → completed →
  # escalated → canceled, then newest-first. There is no status filter.
  @list_status :all

  def empty_message, do: "No todos yet. Add one to get started."

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
      :completed -> "todo-row--completed"
      :canceled -> "todo-row--canceled"
      :deleted -> "todo-row--deleted"
      _ -> nil
    end
  end

  @doc """
  Mount assigns. `params` carries the optional `?highlight=<todo_id>` (set when arriving
  from the team log): `highlight_id` is assigned **before** `load_first_page` so the matching
  first-page row bakes the `todo-row-highlight` class at stream time (server-side, like the
  `todo-row--*` effects — no dependence on JS). A target beyond the loaded cursor is then
  fetched and inserted at the top. A deleted/unknown id is ignored.
  """
  def mount_assigns(socket, params \\ %{}) do
    socket
    |> assign(:todo_form, nil)
    |> assign(:editing, nil)
    |> assign(:canceling_todo, nil)
    |> assign(:cancel_form, nil)
    |> assign(:highlight_id, normalize_highlight(params))
    |> assign(:row_effects, %{})
    |> load_first_page()
    |> insert_offpage_highlight()
    |> push_highlight_scroll()
  end

  # After the connected render the client patches the DOM and mounts hooks, *then* dispatches
  # pushed events — so this beats LiveView's own scroll-to-top on navigation and the row is
  # laid out by the time we scroll. Only pushed when the row is actually present.
  defp push_highlight_scroll(%{assigns: %{highlight_id: nil}} = socket), do: socket

  defp push_highlight_scroll(%{assigns: %{highlight_id: id, loaded_ids: loaded}} = socket) do
    if connected?(socket) and MapSet.member?(loaded, id) do
      push_event(socket, "highlight_todo", %{id: id})
    else
      socket
    end
  end

  defp normalize_highlight(%{"highlight" => id}) when is_binary(id) and id != "", do: id
  defp normalize_highlight(_), do: nil

  defp insert_offpage_highlight(%{assigns: %{highlight_id: nil}} = socket), do: socket

  defp insert_offpage_highlight(%{assigns: %{highlight_id: id, loaded_ids: loaded}} = socket) do
    if MapSet.member?(loaded, id) do
      socket
    else
      case Todos.get_listed_todo(socket.assigns.current_scope, id) do
        {:ok, todo} ->
          socket
          |> stream_insert(:todos, todo, dom_id: &todo_dom_id(socket, &1), at: 0)
          |> assign(:empty?, false)
          |> assign(:loaded_ids, MapSet.put(loaded, id))
          |> assign(:audit_by_id, Map.merge(socket.assigns.audit_by_id, audit_for_todos([todo])))

        _ ->
          socket
      end
    end
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

    case Todos.list_todos_page(scope, status: @list_status) do
      :not_authorise ->
        socket
        |> stream(:todos, [], reset: true)
        |> assign(
          cursor: nil,
          end?: true,
          empty?: true,
          audit_by_id: %{},
          loaded_ids: MapSet.new()
        )

      {:ok, %{rows: todos, cursor: cursor, end?: end?}} ->
        socket
        |> stream(:todos, todos, dom_id: &todo_dom_id(socket, &1), reset: true)
        |> assign(
          cursor: cursor,
          end?: end?,
          empty?: todos == [],
          audit_by_id: audit_for_todos(todos),
          loaded_ids: MapSet.new(todos, & &1.id)
        )
    end
  end

  def load_more(socket) do
    scope = socket.assigns.current_scope
    cursor = socket.assigns[:cursor]

    case Todos.list_todos_page(scope, status: @list_status, cursor: cursor) do
      :not_authorise ->
        socket

      {:ok, %{rows: todos, cursor: new_cursor, end?: end?}} ->
        socket
        |> stream(:todos, todos, dom_id: &todo_dom_id(socket, &1), at: -1)
        |> assign(
          cursor: new_cursor,
          end?: end?,
          audit_by_id: Map.merge(socket.assigns.audit_by_id, audit_for_todos(todos)),
          loaded_ids: MapSet.union(socket.assigns.loaded_ids, MapSet.new(todos, & &1.id))
        )
    end
  end

  defp audit_for_todos(todos) do
    Todos.list_audit_logs_by_todo(Enum.map(todos, & &1.id))
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
          {:ok, updated} ->
            {:ok, apply_toggle_effect(socket, scope, updated)}

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
      {:ok, canceled} ->
        {:ok,
         socket
         |> close_cancel_modal()
         |> apply_save_effect(scope, canceled, :canceled)}

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

  # The unified list always shows the row; completing flashes the satisfying check
  # animation and leaves the (now muted) row in place, reopening flashes :updated.
  defp apply_toggle_effect(socket, scope, %Todo{} = todo) do
    effect = if Todo.completed?(todo), do: :completed, else: :updated

    socket
    |> put_row_effect(todo.id, effect)
    |> insert_todo_row(scope, todo, effect)
  end

  defp apply_save_effect(socket, scope, %Todo{} = todo, effect) do
    socket
    |> put_row_effect(todo.id, effect)
    |> insert_todo_row(scope, todo, effect)
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

  defp put_row_effect(socket, todo_id, effect) do
    assign(socket, :row_effects, Map.put(socket.assigns.row_effects || %{}, todo_id, effect))
  end

  defp stream_insert_todo(socket, %Todo{} = todo) do
    stream_insert(socket, :todos, todo, dom_id: &todo_dom_id(socket, &1))
  end
end
