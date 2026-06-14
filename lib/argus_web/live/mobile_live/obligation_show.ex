defmodule ArgusWeb.MobileLive.ObligationShow do
  use ArgusWeb, :live_view

  alias Argus.Authorization
  alias Argus.Entities
  alias Argus.Obligations
  alias Argus.Obligations.{Obligation, Recurrence, Urgency}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} active={:obligations}>
      <div id="mobile-obligation-show">
        <.link
          navigate={~p"/m/#{@current_scope.entity.slug}/obligations"}
          class="text-sm text-base-content/60 flex items-center gap-1"
        >
          <.icon name="hero-chevron-left-mini" class="size-4" /> Obligations
        </.link>

        <div class="mt-2 flex items-start justify-between gap-2">
          <h1 class="text-xl font-semibold">{@obligation.title}</h1>
          <div class="flex items-center gap-1 shrink-0">
            <button
              :if={@live? and Authorization.can?(@current_scope, :edit_obligation)}
              id="m-edit-obligation-btn"
              type="button"
              phx-click="open_edit_modal"
              class="btn btn-ghost btn-xs"
            >
              <.icon name="hero-pencil-square-mini" class="size-4" />
            </button>
            <.urgency_badge urgency={@urgency} />
          </div>
        </div>
        <p class="text-sm text-base-content/60">
          {@obligation.obligation_type.name} · due {format_date(@obligation.due_by)} · {due_label(
            @obligation.due_by,
            @today
          )}
        </p>

        <div class="mt-3 flex flex-wrap gap-1">
          <span class="badge badge-primary badge-soft gap-1">
            <.icon name="hero-user-mini" class="size-3" />{@obligation.primary_assignee.email}
          </span>
          <span :for={c <- @obligation.collaborators} class="badge badge-ghost gap-1">
            {c.user.email}
          </span>
        </div>

        <ol id="event-timeline" class="mt-5 space-y-3">
          <li
            :for={event <- @obligation.events}
            id={"m-event-#{event.id}"}
            data-status={event.status}
            class="border-l-2 border-base-300 pl-3"
          >
            <div class="flex items-center justify-between">
              <span class="font-medium text-sm">{humanize_status(event.status)}</span>
              <span class="text-xs text-base-content/50">{format_datetime(event.inserted_at)}</span>
            </div>
            <div class="mt-1 flex items-start justify-between gap-2">
              <div
                :if={@editing_note_id != event.id and is_binary(event.note)}
                class="text-sm text-base-content/70"
              >
                {event.note}
              </div>
              <div
                :if={@editing_note_id != event.id and is_nil(event.note)}
                class="text-sm text-base-content/40 italic"
              >
                No note
              </div>
              <button
                :if={
                  @editing_note_id != event.id and
                    Obligations.note_editable?(@current_scope, event, @obligation)
                }
                id={"m-edit-note-#{event.id}"}
                type="button"
                phx-click="edit_note"
                phx-value-event_id={event.id}
                class="btn btn-ghost btn-xs shrink-0"
              >
                Edit
              </button>
            </div>
            <.form
              :if={@editing_note_id == event.id}
              for={@note_form}
              id={"m-note-form-#{event.id}"}
              phx-submit="save_note"
              class="mt-2 space-y-2"
            >
              <input type="hidden" name="event_id" value={event.id} />
              <.input field={@note_form[:note]} type="textarea" label="Note" />
              <div class="flex gap-2">
                <.button class="btn btn-primary btn-sm" phx-disable-with="Saving…">Save</.button>
                <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_note_edit">
                  Cancel
                </button>
              </div>
            </.form>
          </li>
        </ol>

        <div :if={@live?} class="mt-6 grid grid-cols-1 gap-2">
          <button
            :if={Authorization.can?(@current_scope, :start_progress, @obligation)}
            id="m-start-progress-btn"
            type="button"
            phx-click="start_progress"
            class="btn btn-outline btn-lg"
          >
            Update progress
          </button>
          <button
            :if={Authorization.can?(@current_scope, :mark_done, @obligation)}
            id="m-done-btn"
            type="button"
            phx-click="open_done_modal"
            class="btn btn-primary btn-lg"
          >
            Mark done
          </button>
          <button
            :if={Authorization.can?(@current_scope, :cancel_obligation)}
            id="m-cancel-btn"
            type="button"
            phx-click="cancel"
            class="btn btn-ghost btn-error btn-lg"
          >
            Cancel
          </button>
        </div>
      </div>

      <div :if={@show_edit_modal} id="m-edit-modal" class="modal modal-bottom modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Edit obligation</h3>
          <.form
            for={@edit_form}
            id="m-edit-obligation-form"
            phx-submit="save_obligation"
            class="mt-2 space-y-3"
          >
            <.input field={@edit_form[:title]} type="text" label="Title" required />
            <.input field={@edit_form[:due_by]} type="date" label="Due by" required />
            <.input
              field={@edit_form[:primary_assignee_id]}
              type="select"
              label="Primary assignee"
              options={@member_options}
              required
            />
            <div class="fieldset mb-2">
              <label class="label mb-1" for="m-edit-collaborator-ids">Collaborators</label>
              <select
                id="m-edit-collaborator-ids"
                name="obligation[collaborator_ids][]"
                multiple
                class="select w-full h-32"
              >
                <option
                  :for={{label, id} <- @member_options}
                  value={id}
                  selected={collaborator_selected?(@edit_collaborator_ids, id)}
                >
                  {label}
                </option>
              </select>
              <p class="text-xs text-base-content/50 mt-1">
                Hold ⌘/Ctrl to select more than one. Deselect all to remove collaborators.
              </p>
            </div>
            <div class="modal-action">
              <button type="button" class="btn" phx-click="close_edit_modal">Cancel</button>
              <.button class="btn btn-primary" phx-disable-with="Saving…">Save</.button>
            </div>
          </.form>
        </div>
      </div>

      <div :if={@show_done_modal} id="m-done-modal" class="modal modal-bottom modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Mark done</h3>
          <.form for={@done_form} id="m-done-form" phx-submit="complete" class="mt-2 space-y-3">
            <.input
              :if={@recurring?}
              field={@done_form[:next_due_by]}
              type="date"
              label="Next due date"
              required
            />
            <.input
              :if={@obligation.complete_note_required}
              field={@done_form[:note]}
              type="textarea"
              label="Completion note"
              required
            />
            <div class="modal-action">
              <button type="button" class="btn" phx-click="close_done_modal">Cancel</button>
              <.button class="btn btn-primary" phx-disable-with="Saving…">Complete</.button>
            </div>
          </.form>
        </div>
      </div>
    </Layouts.mobile_app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(:show_done_modal, false)
     |> assign(:show_edit_modal, false)
     |> assign(:editing_note_id, nil)
     |> assign(:note_form, nil)
     |> assign(:member_options, member_options(scope))
     |> load(id, scope)}
  end

  @impl true
  def handle_event("open_edit_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_edit_modal, true)
     |> assign_edit_form(socket.assigns.obligation)}
  end

  def handle_event("close_edit_modal", _params, socket) do
    {:noreply, assign(socket, :show_edit_modal, false)}
  end

  def handle_event("save_obligation", %{"obligation" => params}, socket) do
    scope = socket.assigns.current_scope

    obligation = socket.assigns.obligation

    attrs = %{
      title: params["title"],
      due_by: parse_date(params["due_by"]),
      primary_assignee_id: params["primary_assignee_id"]
    }

    collaborator_ids = parse_collaborator_ids(params["collaborator_ids"])

    case Obligations.update_obligation(scope, obligation, attrs) do
      {:ok, updated} ->
        case Obligations.update_collaborators(scope, updated, collaborator_ids) do
          {:ok, _} ->
            {:noreply,
             reload(socket)
             |> assign(:show_edit_modal, false)
             |> put_flash(:info, "Obligation updated.")}

          :not_authorise ->
            {:noreply, put_flash(socket, :error, "Not authorized to update collaborators.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not update collaborators.")}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:edit_form, to_form(changeset, as: "obligation"))
         |> assign(:edit_collaborator_ids, collaborator_ids)}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  def handle_event("edit_note", %{"event_id" => event_id}, socket) do
    case find_event(socket.assigns.obligation.events, event_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Event not found.")}

      event ->
        {:noreply,
         socket
         |> assign(:editing_note_id, event.id)
         |> assign(:note_form, to_form(%{"note" => event.note || ""}, as: :note))}
    end
  end

  def handle_event("cancel_note_edit", _params, socket) do
    {:noreply, socket |> assign(:editing_note_id, nil) |> assign(:note_form, nil)}
  end

  def handle_event("save_note", %{"event_id" => event_id, "note" => %{"note" => note}}, socket) do
    scope = socket.assigns.current_scope

    case find_event(socket.assigns.obligation.events, event_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Event not found.")}

      event ->
        case Obligations.edit_note(scope, event, %{note: note}) do
          {:ok, _} ->
            {:noreply,
             reload(socket)
             |> assign(:editing_note_id, nil)
             |> assign(:note_form, nil)
             |> put_flash(:info, "Note updated.")}

          {:error, :locked} ->
            {:noreply, put_flash(socket, :error, "This note can no longer be edited.")}

          {:error, %Ecto.Changeset{}} ->
            {:noreply, put_flash(socket, :error, "Could not save note.")}
        end
    end
  end

  def handle_event("start_progress", _params, socket) do
    case Obligations.start_progress(socket.assigns.current_scope, socket.assigns.obligation) do
      {:ok, _} -> {:noreply, reload(socket) |> put_flash(:info, "Progress updated.")}
      {:error, :not_open} -> {:noreply, put_flash(socket, :error, "Already in progress.")}
      :not_authorise -> {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  def handle_event("open_done_modal", _params, socket) do
    {:noreply, assign(socket, :show_done_modal, true)}
  end

  def handle_event("close_done_modal", _params, socket) do
    {:noreply, assign(socket, :show_done_modal, false)}
  end

  def handle_event("complete", %{"done" => params}, socket) do
    scope = socket.assigns.current_scope

    attrs = %{note: params["note"], next_due_by: parse_date(params["next_due_by"])}

    case Obligations.complete(scope, socket.assigns.obligation, attrs) do
      {:ok, _completed, _spawned} ->
        {:noreply,
         socket
         |> put_flash(:info, "Obligation completed.")
         |> push_navigate(to: ~p"/m/#{scope.entity.slug}/obligations")}

      {:error, :next_due_required} ->
        {:noreply,
         put_flash(socket, :error, "Next due date is required for recurring obligations.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not complete obligation.")}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  def handle_event("cancel", _params, socket) do
    scope = socket.assigns.current_scope

    case Obligations.cancel_obligation(scope, socket.assigns.obligation, %{}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Obligation cancelled.")
         |> push_navigate(to: ~p"/m/#{scope.entity.slug}/obligations")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not cancel.")}
    end
  end

  defp load(socket, id, scope) do
    obligation =
      scope
      |> Obligations.get_obligation!(id)
      |> Map.update!(:events, &Enum.sort_by(&1, fn e -> e.inserted_at end, DateTime))

    today = Urgency.today_for(scope.entity.timezone)

    recurring? =
      Recurrence.recurring?(obligation.obligation_type) and is_nil(obligation.series_ended_at)

    socket
    |> assign(:obligation, obligation)
    |> assign(:today, today)
    |> assign(:urgency, Urgency.classify(obligation.obligation_type, obligation.due_by, today))
    |> assign(:live?, live_cycle?(obligation))
    |> assign(:recurring?, recurring?)
    |> assign(
      :done_form,
      to_form(%{"note" => "", "next_due_by" => suggestion(obligation, recurring?)}, as: :done)
    )
    |> assign_edit_form(obligation)
  end

  defp reload(socket) do
    load(socket, socket.assigns.obligation.id, socket.assigns.current_scope)
  end

  defp assign_edit_form(socket, obligation) do
    socket
    |> assign(:edit_collaborator_ids, Enum.map(obligation.collaborators, & &1.user_id))
    |> assign(
      :edit_form,
      to_form(
        %{
          "title" => obligation.title,
          "due_by" => iso_date(obligation.due_by),
          "primary_assignee_id" => obligation.primary_assignee_id
        },
        as: "obligation"
      )
    )
  end

  defp collaborator_selected?(ids, id) do
    Enum.any?(ids, &(to_string(&1) == to_string(id)))
  end

  defp parse_collaborator_ids(nil), do: []

  defp parse_collaborator_ids(ids) when is_list(ids) do
    ids
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  defp parse_collaborator_ids(id), do: [id]

  defp find_event(events, event_id) do
    Enum.find(events, &(to_string(&1.id) == to_string(event_id)))
  end

  defp member_options(scope) do
    Entities.list_entity_members(scope.entity)
    |> Enum.map(fn {user, _membership} -> {user.email, user.id} end)
  end

  defp iso_date(%Date{} = date), do: Date.to_iso8601(date)
  defp iso_date(_), do: ""

  defp suggestion(obligation, true) do
    case Recurrence.next_due_suggestion(obligation.obligation_type, obligation.due_by) do
      %Date{} = date -> Date.to_iso8601(date)
      _ -> ""
    end
  end

  defp suggestion(_obligation, false), do: ""

  defp live_cycle?(%Obligation{status: "active", completed_at: nil}), do: true
  defp live_cycle?(_), do: false

  defp humanize_status("in_progress"), do: "In progress"
  defp humanize_status(status), do: String.capitalize(status)

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
