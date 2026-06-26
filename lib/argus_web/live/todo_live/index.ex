defmodule ArgusWeb.TodoLive.Index do
  use ArgusWeb, :live_view

  alias ArgusWeb.ModalEscape
  alias ArgusWeb.TodoLive.{ActivityFormat, IndexHelpers}
  alias Argus.Todos.Todo

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="todos-page">
        <.header>
          Todos
          <:subtitle>Quick team tasks — separate from duties.</:subtitle>
          <:actions>
            <button
              id="new-todo-btn"
              type="button"
              phx-click="new"
              class="btn btn-primary btn-sm"
            >
              <.icon name="hero-plus-mini" class="size-4" /> New todo
            </button>
          </:actions>
        </.header>

        <form id="todo-status-filter" phx-change="set_status" class="mt-4 flex items-center gap-2">
          <label for="todo-status-select" class="text-sm text-base-content/70">Show</label>
          <select id="todo-status-select" name="status" class="select select-sm w-auto">
            <option
              :for={{value, label} <- IndexHelpers.statuses()}
              value={value}
              selected={@status == IndexHelpers.parse_status(value)}
            >
              {label}
            </option>
          </select>
        </form>

        <ul
          id="todos-list"
          class="mt-6 divide-y divide-base-300 rounded-box border border-base-300"
          phx-update="stream"
          phx-viewport-bottom={!@end? && "load_more"}
        >
          <li
            :for={{_dom_id, todo} <- @streams.todos}
            id={IndexHelpers.todo_dom_id(@socket, todo)}
            phx-hook="TodoRowEffect"
            data-todo-id={todo.id}
            data-effect={IndexHelpers.row_effect_name(@row_effects, todo.id)}
            class={[
              "p-3 space-y-2 border-l-4 border-transparent",
              IndexHelpers.row_muted?(todo) && "opacity-60",
              IndexHelpers.row_effect_class(@row_effects, todo.id)
            ]}
          >
            <div class="flex items-start gap-3">
              <input
                :if={Todo.active?(todo)}
                id={"todo-complete-#{todo.id}"}
                type="checkbox"
                class="checkbox checkbox-sm mt-1"
                checked={Todo.completed?(todo)}
                phx-click="toggle_complete"
                phx-value-id={todo.id}
              />
              <div :if={not Todo.active?(todo)} class="w-4 shrink-0" aria-hidden="true" />
              <div class="flex-1 min-w-0 space-y-1">
                <div class="flex flex-wrap items-center gap-2">
                  <div class={[
                    "font-medium",
                    IndexHelpers.title_strike?(todo) && "line-through text-base-content/60"
                  ]}>
                    {todo.title}
                  </div>
                  <.todo_badge todo={todo} />
                </div>
                <.link
                  :if={Todo.escalated?(todo) && todo.escalated_obligation_id}
                  id={"todo-view-duty-#{todo.id}"}
                  navigate={
                    ~p"/entities/#{@current_scope.entity.slug}/obligations/#{todo.escalated_obligation_id}"
                  }
                  class="text-xs link link-primary"
                >
                  View duty
                </.link>
              </div>
              <.todo_actions_menu todo={todo} current_scope={@current_scope} />
            </div>
            <.audit_trail
              todo={todo}
              logs={Map.get(@audit_by_id, todo.id, [])}
              expanded?={@expanded_audit_id == todo.id}
            />
          </li>
        </ul>
        <p :if={@empty?} id="todos-empty" class="mt-6 text-sm text-base-content/60">
          {IndexHelpers.empty_message(@status)}
        </p>
      </div>

      <div :if={@todo_form} id="todo-modal" class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">{@modal_title}</h3>
          <.form
            for={@todo_form}
            id="todo-form"
            phx-change="validate"
            phx-submit="save"
            class="mt-4 space-y-3"
          >
            <.input field={@todo_form[:title]} type="text" label="Title" required />
            <div class="modal-action">
              <button type="button" class="btn" phx-click="dismiss_form">Cancel</button>
              <.button class="btn btn-primary" phx-disable-with="Saving…">{@submit_label}</.button>
            </div>
          </.form>
        </div>
        <div class="modal-backdrop">
          <button type="button" phx-click="dismiss_form">close</button>
        </div>
      </div>

      <div :if={@canceling_todo} id="todo-cancel-modal" class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Cancel todo</h3>
          <p class="text-sm text-base-content/70 mt-1">
            Todos older than 48 hours cannot be deleted. Add a note to cancel <span class="font-medium">{@canceling_todo.title}</span>.
          </p>
          <.form
            for={@cancel_form}
            id="todo-cancel-form"
            phx-submit="submit_cancel"
            class="mt-4 space-y-3"
          >
            <.input field={@cancel_form[:note]} type="textarea" label="Cancel note" required />
            <div class="modal-action">
              <button type="button" class="btn" phx-click="dismiss_cancel">Back</button>
              <.button class="btn btn-error" phx-disable-with="Canceling…">Cancel todo</.button>
            </div>
          </.form>
        </div>
        <div class="modal-backdrop">
          <button type="button" phx-click="dismiss_cancel">close</button>
        </div>
      </div>
    </Layouts.app>
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
        class="text-xs text-base-content/50 hover:text-base-content"
      >
        {if @expanded?, do: "Hide history", else: "Show history (#{length(@logs)})"}
      </button>
      <ul
        :if={@expanded?}
        id={"todo-audit-#{@todo.id}"}
        class="mt-1 space-y-1 text-xs text-base-content/60"
      >
        <li :for={log <- @logs}>
          <span class="font-medium">{ActivityFormat.audit_action_label(log.action)}</span>
          by {ActivityFormat.display_name(log.user)}
          <span :if={log.field}>
            — {log.field}: {log.old_value || "—"} → {log.new_value || "—"}
          </span>
          <span class="text-base-content/40"> · {ActivityFormat.format_time(log.inserted_at)}</span>
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
  def handle_event("new", _params, socket) do
    {:noreply, IndexHelpers.open_modal(socket, %Todo{}, nil, "New todo", "Create")}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    IndexHelpers.handle_edit(socket, id) |> IndexHelpers.handle_result()
  end

  def handle_event("close_modal_on_escape", _params, socket) do
    {:noreply, ModalEscape.close_todo_modal(socket)}
  end

  def handle_event("dismiss_form", _params, socket) do
    {:noreply, IndexHelpers.close_modal(socket)}
  end

  def handle_event("validate", params, socket) do
    {:noreply, IndexHelpers.handle_validate(socket, params)}
  end

  def handle_event("save", params, socket) do
    IndexHelpers.handle_save(socket, params) |> IndexHelpers.handle_result()
  end

  def handle_event("toggle_complete", params, socket) do
    IndexHelpers.handle_toggle(socket, params) |> IndexHelpers.handle_result()
  end

  def handle_event("delete", params, socket) do
    IndexHelpers.handle_delete(socket, params) |> IndexHelpers.handle_result()
  end

  def handle_event("open_cancel", params, socket) do
    IndexHelpers.handle_open_cancel(socket, params) |> IndexHelpers.handle_result()
  end

  def handle_event("submit_cancel", params, socket) do
    IndexHelpers.handle_submit_cancel(socket, params) |> IndexHelpers.handle_result()
  end

  def handle_event("dismiss_cancel", _params, socket) do
    {:noreply, IndexHelpers.close_cancel_modal(socket)}
  end

  def handle_event("set_status", params, socket) do
    IndexHelpers.handle_set_status(socket, params) |> IndexHelpers.handle_result()
  end

  def handle_event("todo_action", params, socket) do
    IndexHelpers.handle_todo_action(socket, params) |> IndexHelpers.handle_result()
  end

  def handle_event("finish_row_effect", params, socket) do
    IndexHelpers.handle_finish_row_effect(socket, params) |> IndexHelpers.handle_result()
  end

  def handle_event("toggle_audit", %{"id" => id}, socket) do
    expanded =
      if socket.assigns.expanded_audit_id == id, do: nil, else: id

    {:noreply, assign(socket, :expanded_audit_id, expanded)}
  end

  def handle_event("load_more", _params, socket) do
    IndexHelpers.handle_load_more(socket) |> IndexHelpers.handle_result()
  end
end
