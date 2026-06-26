defmodule ArgusWeb.ObligationLive.Form do
  use ArgusWeb, :live_view

  alias ArgusWeb.ObligationLive.CreateForm

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="obligation-form" class="mx-auto max-w-xl">
        <.form
          for={@form}
          id="obligation-create-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-1"
        >
          <div class="text-2xl font-bold mb-2">New duty</div>
          <.char_count_input field={@form[:title]} label="Title" max={60} required />
          <div class="flex items-center gap-4">
            <.input
              field={@form[:obligation_type_id]}
              type="select"
              label="Type"
              options={@type_options}
              prompt="Choose a type"
              required
            />
            <div class="mt-6">
              <.input field={@form[:someday]} type="checkbox" label="No due date (Someday)" />
            </div>
            <.input :if={!someday?(@form)} field={@form[:due_by]} type="date" label="Due by" required />
          </div>
          <.input field={@form[:open_note]} type="textarea" label="Open note" required />
          <div class="fieldset">
            <.input
              field={@form[:primary_assignee_id]}
              type="select"
              label="Primary assignee"
              options={@member_options}
              prompt="Unassigned"
            />
            <label class="label" for="collaborator-ids">Also collaborating (optional)</label>
            <select
              id="collaborator-ids"
              name="obligation[collaborator_ids][]"
              multiple
              class="select w-full h-24"
            >
              <option :for={{label, id} <- @member_options} value={id}>{label}</option>
            </select>
            <p class="text-xs text-base-content/50">
              Hold ⌘/Ctrl to select more than one.
            </p>
          </div>
        </.form>

        <button
          type="submit"
          form="obligation-create-form"
          class="btn btn-primary mt-4"
          phx-disable-with="Creating..."
        >
          Create duty
        </button>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    if Argus.Authorization.can?(socket.assigns.current_scope, :create_obligation) do
      {:ok, CreateForm.load_form(socket, params)}
    else
      {:ok,
       socket
       |> put_flash(:error, "You are not authorized to create duties.")
       |> push_navigate(to: ~p"/entities/#{socket.assigns.current_scope.entity.slug}")}
    end
  end

  @impl true
  def handle_event("validate", %{"obligation" => params}, socket) do
    CreateForm.validate(socket, params)
  end

  def handle_event("save", %{"obligation" => params}, socket) do
    CreateForm.save(socket, params, fn scope, obligation ->
      ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}"
    end)
  end

  # The app shell binds a global Escape keydown; this page has no modals.
  def handle_event("close_modal_on_escape", _params, socket) do
    {:noreply, socket}
  end

  defp someday?(form), do: Phoenix.HTML.Form.normalize_value("checkbox", form[:someday].value)
end
