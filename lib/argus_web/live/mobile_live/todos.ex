defmodule ArgusWeb.MobileLive.Todos do
  use ArgusWeb, :live_view

  alias ArgusWeb.ModalEscape
  alias ArgusWeb.TodoLive.IndexHelpers
  alias Argus.Todos.Todo

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app
      flash={@flash}
      current_scope={@current_scope}
      active={if(@live_action == :new, do: :new_todo, else: :todos)}
    >
      <div id="m-todos-page" class="p-4">
        <div class="flex items-center justify-between gap-2 mb-3">
          <div class="font-semibold text-xl">Todos</div>
          <button
            id="m-new-todo-btn"
            type="button"
            phx-click="new"
            class="btn btn-primary btn-sm gap-1"
          >
            <.icon name="hero-plus-mini" class="size-4" /> New
          </button>
        </div>

        <p class="text-xs text-base-content/60 mb-3">
          Quick team tasks — separate from duties.
        </p>

        <ul
          :if={@todos != []}
          id="m-todos-list"
          class="divide-y divide-base-300 rounded-box border border-base-300"
        >
          <li
            :for={todo <- @todos}
            id={"m-todo-#{todo.id}"}
            class={[
              "p-3 space-y-2",
              Todo.completed?(todo) && "opacity-60"
            ]}
          >
            <div class="flex items-start gap-3">
              <input
                id={"m-todo-complete-#{todo.id}"}
                type="checkbox"
                class="checkbox checkbox-sm mt-1"
                checked={Todo.completed?(todo)}
                phx-click="toggle_complete"
                phx-value-id={todo.id}
              />
              <div class="flex-1 min-w-0">
                <div class={[
                  "font-medium",
                  Todo.completed?(todo) && "line-through text-base-content/60"
                ]}>
                  {todo.title}
                </div>
                <div class="text-xs text-base-content/50 mt-0.5">
                  {display_name(todo.created_by)}
                </div>
              </div>
              <div class="flex shrink-0 gap-1">
                <button
                  type="button"
                  phx-click="edit"
                  phx-value-id={todo.id}
                  class="btn btn-ghost btn-xs"
                >
                  Edit
                </button>
                <button
                  type="button"
                  phx-click="delete"
                  phx-value-id={todo.id}
                  data-confirm="Delete this todo?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </div>
            </div>
            <.audit_trail
              todo={todo}
              logs={Map.get(@audit_by_id, todo.id, [])}
              expanded?={@expanded_audit_id == todo.id}
            />
          </li>
        </ul>
        <p :if={@todos == []} id="m-todos-empty" class="text-sm text-base-content/60">
          No todos yet. Add one to get started.
        </p>

        <.team_activity :if={@entity_activity != []} logs={@entity_activity} />
      </div>

      <div :if={@todo_form} id="m-todo-modal" class="modal modal-bottom modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">{@modal_title}</h3>
          <.form
            for={@todo_form}
            id="m-todo-form"
            phx-change="validate"
            phx-submit="save"
            class="mt-4 space-y-3"
          >
            <.input field={@todo_form[:title]} type="text" label="Title" required />
            <div class="flex gap-2 pt-2">
              <button type="button" class="btn flex-1" phx-click="cancel">Cancel</button>
              <.button class="btn btn-primary flex-1" phx-disable-with="Saving…">
                {@submit_label}
              </.button>
            </div>
          </.form>
        </div>
        <div class="modal-backdrop">
          <button type="button" phx-click="cancel">close</button>
        </div>
      </div>
    </Layouts.mobile_app>
    """
  end

  attr :logs, :list, required: true

  defp team_activity(assigns) do
    ~H"""
    <div id="m-team-activity" class="mt-6">
      <h3 class="text-sm font-semibold text-base-content/70">Team activity</h3>
      <ul class="mt-2 space-y-1 text-xs text-base-content/60">
        <li :for={log <- @logs}>
          {audit_action_label(log.action)}{activity_subject(log)} · {display_name(log.user)}
        </li>
      </ul>
    </div>
    """
  end

  attr :todo, Todo, required: true
  attr :logs, :list, required: true
  attr :expanded?, :boolean, required: true

  defp audit_trail(assigns) do
    ~H"""
    <div :if={@logs != []} class="pl-8">
      <button
        type="button"
        phx-click="toggle_audit"
        phx-value-id={@todo.id}
        class="text-xs text-base-content/50"
      >
        {if @expanded?, do: "Hide history", else: "History (#{length(@logs)})"}
      </button>
      <ul
        :if={@expanded?}
        id={"m-todo-audit-#{@todo.id}"}
        class="mt-1 space-y-1 text-xs text-base-content/60"
      >
        <li :for={log <- @logs}>
          {audit_action_label(log.action)} · {display_name(log.user)}
        </li>
      </ul>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, IndexHelpers.mount_assigns(socket)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    socket =
      case socket.assigns.live_action do
        :new ->
          IndexHelpers.open_modal(socket, %Todo{}, nil, "New todo", "Create")

        :index ->
          IndexHelpers.close_modal(socket)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply,
     socket
     |> push_patch(to: ~p"/m/#{socket.assigns.current_scope.entity.slug}/todos/new")}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    IndexHelpers.handle_edit(socket, id) |> IndexHelpers.handle_result()
  end

  def handle_event("close_modal_on_escape", _params, socket) do
    {:noreply, ModalEscape.close_todo_modal(socket)}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, socket |> IndexHelpers.close_modal() |> leave_new_todo_route()}
  end

  def handle_event("validate", params, socket) do
    {:noreply, IndexHelpers.handle_validate(socket, params)}
  end

  def handle_event("save", params, socket) do
    case IndexHelpers.handle_save(socket, params) do
      {:ok, socket} -> {:noreply, leave_new_todo_route(socket)}
      result -> IndexHelpers.handle_result(result)
    end
  end

  def handle_event("toggle_complete", params, socket) do
    IndexHelpers.handle_toggle(socket, params) |> IndexHelpers.handle_result()
  end

  def handle_event("delete", params, socket) do
    IndexHelpers.handle_delete(socket, params) |> IndexHelpers.handle_result()
  end

  def handle_event("toggle_audit", %{"id" => id}, socket) do
    expanded =
      if socket.assigns.expanded_audit_id == id, do: nil, else: id

    {:noreply, assign(socket, :expanded_audit_id, expanded)}
  end

  defp display_name(%{username: u}) when is_binary(u) and u != "", do: u
  defp display_name(%{email: e}) when is_binary(e), do: e
  defp display_name(_), do: "Unknown"

  defp audit_action_label("created"), do: "Created"
  defp audit_action_label("updated"), do: "Updated"
  defp audit_action_label("completed"), do: "Done"
  defp audit_action_label("reopened"), do: "Reopened"
  defp audit_action_label("deleted"), do: "Deleted"
  defp audit_action_label(other), do: other

  defp activity_subject(%{action: "deleted", old_value: title}) when is_binary(title),
    do: " \"#{title}\""

  defp activity_subject(%{todo: %{title: title}}) when is_binary(title), do: " \"#{title}\""
  defp activity_subject(_), do: ""

  defp leave_new_todo_route(socket) do
    if socket.assigns.live_action == :new do
      push_patch(socket, to: ~p"/m/#{socket.assigns.current_scope.entity.slug}/todos")
    else
      socket
    end
  end
end
