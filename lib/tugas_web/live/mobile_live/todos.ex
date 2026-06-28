defmodule TugasWeb.MobileLive.Todos do
  use TugasWeb, :live_view

  alias TugasWeb.ModalEscape
  alias TugasWeb.TodoLive.IndexHelpers
  alias Tugas.Todos.Todo

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app
      flash={@flash}
      current_scope={@current_scope}
      nav_context={:todos}
      nav_highlight={if(@live_action == :new, do: :new_todo, else: nil)}
    >
      <div id="m-todos-page" class="p-4" phx-hook="TodoHighlight" data-highlight-id={@highlight_id}>
        <div class="flex items-center justify-between gap-2 mb-3">
        </div>
        <ul
          id="m-todos-list"
          class="divide-base-400"
          phx-update="stream"
          phx-viewport-bottom={!@end? && "load_more"}
        >
          <li
            :for={{_dom_id, todo} <- @streams.todos}
            id={IndexHelpers.todo_dom_id(@socket, todo)}
            phx-hook="TodoRowEffect"
            data-todo-id={todo.id}
            data-effect={IndexHelpers.row_effect_name(@row_effects, todo.id)}
            data-menu-id={"m-todo-actions-#{todo.id}"}
            class={[
              "px-2 py-4 border select-none mb-2 rounded shadow",
              IndexHelpers.row_muted?(todo) && "opacity-60",
              @highlight_id == todo.id && "todo-row-highlight",
              IndexHelpers.row_effect_class(@row_effects, todo.id)
            ]}
          >
            <div class="flex items-start gap-2">
              <input
                :if={Todo.active?(todo)}
                id={"m-todo-complete-#{todo.id}"}
                type="checkbox"
                class="checkbox checkbox-lg mt-0.5"
                checked={Todo.completed?(todo)}
                phx-click="toggle_complete"
                phx-value-id={todo.id}
              />
              <div :if={not Todo.active?(todo)} class="w-6 shrink-0" aria-hidden="true" />
              <div class="flex-1 min-w-0 space-y-1">
                <div class="flex flex-wrap items-center gap-2">
                  <div class={[
                    "font-medium text-lg",
                    IndexHelpers.title_strike?(todo) && "line-through text-base-content/60"
                  ]}>
                    {todo.title}
                  </div>
                  <.todo_badge todo={todo} />
                </div>
                <.link
                  :if={Todo.escalated?(todo) && todo.escalated_duty_id}
                  id={"m-todo-view-duty-#{todo.id}"}
                  navigate={~p"/m/#{@current_scope.entity.slug}/duties/#{todo.escalated_duty_id}"}
                  class="text-xs link link-primary"
                >
                  View duty
                </.link>
              </div>
            </div>
            <.todo_actions_menu todo={todo} current_scope={@current_scope} mobile?={true} />
          </li>
        </ul>
        <p :if={@empty?} id="m-todos-empty" class="text-sm text-base-content/60">
          {IndexHelpers.empty_message()}
        </p>
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
            <.input
              field={@todo_form[:title]}
              type="text"
              label="Title"
              required
              phx-mounted={JS.focus()}
            />
            <div class="flex gap-2 pt-2">
              <button type="button" class="btn flex-1" phx-click="dismiss_form">Cancel</button>
              <.button class="btn btn-primary flex-1" phx-disable-with="Saving…">
                {@submit_label}
              </.button>
            </div>
          </.form>
        </div>
        <div class="modal-backdrop">
          <button type="button" phx-click="dismiss_form">close</button>
        </div>
      </div>

      <div :if={@canceling_todo} id="m-todo-cancel-modal" class="modal modal-bottom modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Cancel todo</h3>
          <p class="text-sm text-base-content/70 mt-1">
            Todos older than 48 hours cannot be deleted. Add a note to cancel <span class="font-medium">{@canceling_todo.title}</span>.
          </p>
          <.form
            for={@cancel_form}
            id="m-todo-cancel-form"
            phx-submit="submit_cancel"
            class="mt-4 space-y-3"
          >
            <.input field={@cancel_form[:note]} type="textarea" label="Cancel note" required />
            <div class="flex gap-2 pt-2">
              <button type="button" class="btn flex-1" phx-click="dismiss_cancel">Back</button>
              <.button class="btn btn-error flex-1" phx-disable-with="Canceling…">
                Cancel todo
              </.button>
            </div>
          </.form>
        </div>
        <div class="modal-backdrop">
          <button type="button" phx-click="dismiss_cancel">close</button>
        </div>
      </div>
    </Layouts.mobile_app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok, IndexHelpers.mount_assigns(socket, params)}
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

  def handle_event("dismiss_form", _params, socket) do
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

  def handle_event("open_cancel", params, socket) do
    IndexHelpers.handle_open_cancel(socket, params) |> IndexHelpers.handle_result()
  end

  def handle_event("submit_cancel", params, socket) do
    IndexHelpers.handle_submit_cancel(socket, params) |> IndexHelpers.handle_result()
  end

  def handle_event("dismiss_cancel", _params, socket) do
    {:noreply, IndexHelpers.close_cancel_modal(socket)}
  end

  def handle_event("todo_action", params, socket) do
    IndexHelpers.handle_todo_action(socket, params) |> IndexHelpers.handle_result()
  end

  def handle_event("finish_row_effect", params, socket) do
    IndexHelpers.handle_finish_row_effect(socket, params) |> IndexHelpers.handle_result()
  end

  def handle_event("load_more", _params, socket) do
    IndexHelpers.handle_load_more(socket) |> IndexHelpers.handle_result()
  end

  defp leave_new_todo_route(socket) do
    if socket.assigns.live_action == :new do
      push_patch(socket, to: ~p"/m/#{socket.assigns.current_scope.entity.slug}/todos")
    else
      socket
    end
  end
end
