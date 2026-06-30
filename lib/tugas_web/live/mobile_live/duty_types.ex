defmodule TugasWeb.MobileLive.DutyTypes do
  use TugasWeb, :live_view

  alias TugasWeb.ModalEscape
  alias Tugas.Authorization
  alias Tugas.Duties
  alias Tugas.Duties.{Recurrence, Type}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} nav_context={:other}>
      <div id="m-duty-types" class="p-4">
        <div class="flex items-center justify-between gap-2 mb-3">
          <div class="font-semibold text-xl">Duty types</div>
          <button
            :if={@can_manage?}
            id="m-new-type-btn"
            type="button"
            phx-click="new"
            class="btn btn-primary btn-sm gap-1"
          >
            <.icon name="hero-plus-mini" class="size-4" /> New Type
          </button>
          <div :if={not @can_manage?} class="w-14"></div>
        </div>

        <p class="text-xs text-base-content/60 mb-3">
          Reusable definitions for recurring and one-off duties.
        </p>

        <ul
          :if={@types != []}
          id="m-types"
          class="divide-y divide-base-300 rounded-box border border-base-300"
        >
          <li
            :for={type <- @types}
            id={"m-type-#{type.id}"}
            class="flex items-center gap-2 p-3"
          >
            <.type_summary type={type} />
            <div :if={@can_manage?} class="flex shrink-0 gap-1">
              <button
                id={"m-clone-type-#{type.id}"}
                type="button"
                phx-click="clone"
                phx-value-id={type.id}
                class="btn btn-ghost btn-xs"
              >
                Clone
              </button>
              <button
                id={"m-edit-type-#{type.id}"}
                type="button"
                phx-click="edit"
                phx-value-id={type.id}
                class="btn btn-ghost btn-xs"
              >
                Edit
              </button>
            </div>
          </li>
        </ul>
        <p :if={@types == []} class="text-sm text-base-content/60">
          No types yet. Create one to get started.
        </p>
      </div>

      <div :if={@type_form} id="m-type-modal" class="modal modal-bottom modal-open">
        <div class="modal-box max-h-[85vh] overflow-y-auto">
          <h3 class="font-bold text-lg">{@modal_title}</h3>
          <.form
            for={@type_form}
            id="m-type-form"
            phx-change="validate"
            phx-submit="save"
            class="mt-4 space-y-3"
          >
            <.input field={@type_form[:name]} type="text" label="Name" required />
            <.input
              field={@type_form[:recurring_interval]}
              type="select"
              label="Recurring interval"
              options={interval_options()}
            />
            <p class="text-xs text-base-content/50 -mt-2">
              Switching to <span class="font-medium">One-off</span>
              stops recurrence for all open duties of this type after their next Done —
              different from <span class="font-medium">End series</span>, which cancels a single cycle.
            </p>
            <.input
              field={@type_form[:complete_documents]}
              type="text"
              label="Required document slots"
              placeholder="receipt, payment_proof"
            />
            <.input
              field={@type_form[:reminder_offsets]}
              type="text"
              label="Reminder offsets (days before due)"
              placeholder="30, 7, 1"
            />
            <div class="modal-action">
              <button type="button" class="btn" phx-click="cancel">Cancel</button>
              <.button class="btn btn-primary" phx-disable-with="Saving…">{@submit_label}</.button>
            </div>
          </.form>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button type="button" phx-click="cancel">close</button>
        </form>
      </div>
    </Layouts.mobile_app>
    """
  end

  attr :type, Type, required: true

  defp type_summary(assigns) do
    ~H"""
    <div class="flex-1 min-w-0">
      <div class="font-medium truncate">{@type.name}</div>
      <div class="text-sm text-base-content/60 truncate">
        {interval_label(@type.recurring_interval)}
        <span :if={@type.complete_documents not in [nil, ""]}>
          · docs: {@type.complete_documents}
        </span>
        <span :if={@type.reminder_offsets not in [nil, ""]}>
          · reminders: {@type.reminder_offsets} days before due
        </span>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:can_manage?, Authorization.can?(socket.assigns.current_scope, :manage_types))
     |> assign(:type_form, nil)
     |> assign(:editing, nil)
     |> load_types()}
  end

  @impl true
  def handle_event("close_modal_on_escape", _params, socket) do
    {:noreply, ModalEscape.close_type_modal(socket)}
  end

  def handle_event("new", _params, socket) do
    {:noreply, open_modal(socket, %Type{}, nil, "New duty type", "Create")}
  end

  def handle_event("clone", %{"id" => id}, socket) do
    source = Duties.get_type!(socket.assigns.current_scope, id)

    template = %Type{
      name: "#{source.name} (copy)",
      recurring_interval: source.recurring_interval,
      complete_documents: source.complete_documents,
      reminder_offsets: source.reminder_offsets
    }

    {:noreply, open_modal(socket, template, nil, "Clone duty type", "Create")}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    type = Duties.get_type!(socket.assigns.current_scope, id)
    {:noreply, open_modal(socket, type, type, "Edit duty type", "Save")}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, assign(socket, type_form: nil, editing: nil)}
  end

  def handle_event("validate", %{"type" => params}, socket) do
    template = socket.assigns.editing || %Type{}
    changeset = Duties.change_type(template, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :type_form, to_form(changeset, as: "type"))}
  end

  def handle_event("save", %{"type" => params}, socket) do
    scope = socket.assigns.current_scope

    result =
      case socket.assigns.editing do
        nil -> Duties.create_type(scope, params)
        %Type{} = type -> Duties.update_type(scope, type, params)
      end

    case result do
      {:ok, _type} ->
        {:noreply,
         socket
         |> put_flash(:info, "Type saved.")
         |> assign(type_form: nil, editing: nil)
         |> load_types()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :type_form, to_form(changeset, as: "type"))}

      :not_authorise ->
        {:noreply,
         socket
         |> put_flash(:error, "Not authorized.")
         |> assign(type_form: nil, editing: nil)}
    end
  end

  defp open_modal(socket, template, editing, title, submit_label) do
    changeset = Duties.change_type(template)

    socket
    |> assign(:type_form, to_form(changeset, as: "type"))
    |> assign(:editing, editing)
    |> assign(:modal_title, title)
    |> assign(:submit_label, submit_label)
  end

  defp load_types(socket) do
    assign(socket, :types, list_types(socket.assigns.current_scope))
  end

  defp list_types(scope) do
    case Duties.list_types(scope) do
      :not_authorise -> []
      types -> types
    end
  end

  defp interval_options do
    Enum.map(Recurrence.intervals(), &{interval_label(&1), &1})
  end

  defp interval_label("none"), do: "One-off"
  defp interval_label("weekly"), do: "Weekly"
  defp interval_label("every_two_weeks"), do: "Every two weeks"
  defp interval_label("monthly"), do: "Monthly"
  defp interval_label("quarterly"), do: "Quarterly"
  defp interval_label("semiannual"), do: "Semi-annual"
  defp interval_label("annual"), do: "Annual"
  defp interval_label("custom"), do: "Custom (pick date each time)"
  defp interval_label(other), do: other
end
