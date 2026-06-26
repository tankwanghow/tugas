defmodule ArgusWeb.MobileLive.ObligationForm do
  @moduledoc """
  Mobile new-obligation form. Mirrors `ObligationLive.Form` but renders in the
  `Layouts.mobile_app` bottom-nav shell; all logic is shared via
  `ArgusWeb.ObligationLive.CreateForm`.
  """
  use ArgusWeb, :live_view

  alias ArgusWeb.ObligationLive.CreateForm

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} active={:new_duty}>
      <div id="m-obligation-form" class="p-4">
        <h1 class="text-lg font-semibold">New duty</h1>

        <.form
          for={@form}
          id="m-obligation-create-form"
          phx-change="validate"
          phx-submit="save"
          class=""
        >
          <.char_count_input field={@form[:title]} label="Title" max={60} required />
          <.input
            field={@form[:obligation_type_id]}
            type="select"
            label="Type"
            options={@type_options}
            prompt="Choose a type"
            required
          />
          <.input field={@form[:someday]} type="checkbox" label="No due date (Someday)" />
          <.input :if={!someday?(@form)} field={@form[:due_by]} type="date" label="Due by" required />
          <.input field={@form[:open_note]} type="textarea" label="Open note" required />
          <.input
            field={@form[:primary_assignee_id]}
            type="select"
            label="Primary assignee"
            options={@member_options}
            prompt="Unassigned"
          />
          <div class="fieldset">
            <label class="label" for="m-collaborator-ids">Also collaborating (optional)</label>
            <select
              id="m-collaborator-ids"
              name="obligation[collaborator_ids][]"
              multiple
              class="select w-full h-24"
            >
              <option :for={{label, id} <- @member_options} value={id}>{label}</option>
            </select>
          </div>
        </.form>

        <button
          type="submit"
          form="m-obligation-create-form"
          class="btn btn-primary w-full mt-4"
          phx-disable-with="Creating..."
        >
          Create duty
        </button>
      </div>
    </Layouts.mobile_app>
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
       |> push_navigate(to: ~p"/m/#{socket.assigns.current_scope.entity.slug}")}
    end
  end

  @impl true
  def handle_event("validate", %{"obligation" => params}, socket) do
    CreateForm.validate(socket, params)
  end

  def handle_event("save", %{"obligation" => params}, socket) do
    CreateForm.save(socket, params, fn scope, obligation ->
      ~p"/m/#{scope.entity.slug}/obligations/#{obligation.id}"
    end)
  end

  # The mobile shell binds a global Escape keydown; this page has no modals.
  def handle_event("close_modal_on_escape", _params, socket) do
    {:noreply, socket}
  end

  defp someday?(form), do: Phoenix.HTML.Form.normalize_value("checkbox", form[:someday].value)
end
