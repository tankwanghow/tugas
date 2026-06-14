defmodule ArgusWeb.ObligationLive.Show do
  use ArgusWeb, :live_view

  alias Argus.Authorization
  alias Argus.Entities
  alias Argus.Obligations
  alias Argus.Obligations.{Obligation, Recurrence, Urgency}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="obligation-show">
        <.header>
          {@obligation.title}
          <:subtitle>
            {@obligation.obligation_type.name} · due {format_date(@obligation.due_by)} · {due_label(
              @obligation.due_by,
              @today
            )}
          </:subtitle>
          <:actions>
            <button
              :if={@live? and Authorization.can?(@current_scope, :edit_obligation)}
              id="edit-obligation-btn"
              type="button"
              phx-click="open_edit_modal"
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-pencil-square-mini" class="size-4" /> Edit
            </button>
            <.urgency_badge urgency={@urgency} />
          </:actions>
        </.header>

        <section :if={@live?} id="obligation-actions" class="flex flex-wrap gap-2">
          <button
            :if={Authorization.can?(@current_scope, :mark_done, @obligation)}
            id="done-btn"
            type="button"
            phx-click="open_done_modal"
            class="btn btn-primary btn-sm"
          >
            Mark done
          </button>
          <button
            :if={Authorization.can?(@current_scope, :cancel_obligation)}
            id="cancel-btn"
            type="button"
            phx-click="open_cancel_modal"
            class="btn btn-outline btn-error btn-sm"
          >
            Cancel
          </button>
          <button
            :if={Authorization.can?(@current_scope, :end_series)}
            id="end-series-btn"
            type="button"
            phx-click="open_end_series_modal"
            class="btn btn-ghost btn-sm"
          >
            End series
          </button>
        </section>

        <section class="mt-6">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
            Assignees
          </h2>
          <div class="mt-2 flex flex-wrap gap-2">
            <span class="badge badge-primary badge-soft gap-1">
              <.icon name="hero-user-mini" class="size-3" />
              {@obligation.primary_assignee.email}
            </span>
            <span :for={c <- @obligation.collaborators} class="badge badge-ghost gap-1">
              <.icon name="hero-user-group-mini" class="size-3" />
              {c.user.email}
            </span>
          </div>
        </section>

        <section :if={@required_docs != []} class="mt-6">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
            Required documents
          </h2>
          <ul class="mt-2 space-y-1 text-sm">
            <li :for={{slot, satisfied?} <- @required_docs} class="flex items-center gap-2">
              <.icon
                name={if satisfied?, do: "hero-check-circle-mini", else: "hero-x-circle-mini"}
                class={["size-4", if(satisfied?, do: "text-success", else: "text-base-content/40")]}
              />
              <span class={if satisfied?, do: "", else: "text-base-content/60"}>{slot}</span>
            </li>
          </ul>
        </section>

        <section class="mt-8">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">Timeline</h2>
          <ol id="event-timeline" class="mt-3 space-y-4">
            <li
              :for={event <- @obligation.events}
              id={"event-#{event.id}"}
              data-status={event.status}
              class={["border-l-2 pl-4", event_accent(event.status)]}
            >
              <div class="flex items-center justify-between gap-3">
                <span class="font-medium">{humanize_status(event.status)}</span>
                <span class="text-xs text-base-content/50">{format_datetime(event.inserted_at)}</span>
              </div>
              <div :if={event.status_by} class="text-xs text-base-content/50">
                by {event.status_by.email}
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
                  id={"edit-note-#{event.id}"}
                  type="button"
                  phx-click="edit_note"
                  phx-value-event_id={event.id}
                  class="btn btn-ghost btn-xs shrink-0"
                >
                  Edit note
                </button>
              </div>
              <.form
                :if={@editing_note_id == event.id}
                for={@note_form}
                id={"note-form-#{event.id}"}
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
              <button
                id={"documents-btn-#{event.id}"}
                type="button"
                phx-click="open_documents_modal"
                phx-value-event_id={event.id}
                class="btn btn-ghost btn-xs mt-2 gap-1"
              >
                <.icon name="hero-paper-clip-mini" class="size-4" />
                Documents ({length(event.documents)})
              </button>
              <ul :if={event.documents != []} class="mt-2 space-y-1 text-sm">
                <li :for={doc <- event.documents} class="flex items-center gap-2">
                  <.icon name="hero-paper-clip-mini" class="size-4 text-base-content/40" />
                  <span :if={doc.document_slot} class="badge badge-xs badge-ghost">
                    {doc.document_slot}
                  </span>
                  <.link
                    href={
                      ~p"/entities/#{@current_scope.entity.slug}/obligations/#{@obligation.id}/documents/#{doc.id}"
                    }
                    target="_blank"
                    class={["link link-hover", doc.voided_at && "line-through text-base-content/40"]}
                  >
                    {file_name(doc)}
                  </.link>
                  <span :if={doc.voided_at} class="badge badge-xs badge-error">voided</span>
                </li>
              </ul>
            </li>
          </ol>
          <button
            :if={@live? and Authorization.can?(@current_scope, :start_progress, @obligation)}
            id="start-progress-btn"
            type="button"
            phx-click="start_progress"
            class="btn btn-outline btn-sm mt-4"
          >
            Update progress
          </button>
        </section>

        <div :if={@audit_logs != []} class="mt-8">
          <button
            :if={not @show_corrections?}
            id="show-corrections-btn"
            type="button"
            phx-click="show_corrections"
            class="btn btn-ghost btn-sm"
          >
            <.icon name="hero-clipboard-document-list-mini" class="size-4" />
            Show corrections ({length(@audit_logs)})
          </button>
          <section :if={@show_corrections?} id="audit-log" class="space-y-3">
            <div class="flex items-center justify-between gap-3">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
                Corrections
              </h2>
              <button
                id="hide-corrections-btn"
                type="button"
                phx-click="hide_corrections"
                class="btn btn-ghost btn-xs"
              >
                Hide
              </button>
            </div>
            <ul class="divide-y divide-base-300 rounded-box border border-base-300 text-sm">
              <li :for={log <- @audit_logs} id={"audit-#{log.id}"} class="p-3 space-y-1">
                <div class="flex items-center justify-between gap-3">
                  <span class="font-medium">{log.field}</span>
                  <span class="text-xs text-base-content/50">{format_datetime(log.inserted_at)}</span>
                </div>
                <div class="text-xs text-base-content/50">by {log.user.email}</div>
                <div class="text-base-content/70">
                  <span :if={log.old_value} class="line-through">{log.old_value}</span>
                  <span :if={log.old_value != nil and log.new_value != nil}> → </span>
                  <span :if={log.new_value}>{log.new_value}</span>
                </div>
              </li>
            </ul>
          </section>
        </div>

        <section :if={length(@series) > 1} id="series-history" class="mt-8">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
            Series history
          </h2>
          <ul class="mt-3 divide-y divide-base-300 rounded-box border border-base-300">
            <li
              :for={cycle <- @series}
              id={"series-cycle-#{cycle.id}"}
              class="flex items-center gap-3 p-3"
            >
              {cycle_marker(cycle, @obligation.id)}
              <div class="flex-1 text-sm">
                due {format_date(cycle.due_by)}
              </div>
              <.link
                :if={cycle.id != @obligation.id}
                navigate={~p"/entities/#{@current_scope.entity.slug}/obligations/#{cycle.id}"}
                class="link link-hover text-sm"
              >
                View
              </.link>
              <span :if={cycle.id == @obligation.id} class="text-sm text-base-content/50">
                viewing
              </span>
            </li>
          </ul>
        </section>
      </div>

      <div :if={@show_edit_modal} id="edit-modal" class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Edit obligation</h3>
          <.form for={@edit_form} id="edit-obligation-form" phx-submit="save_obligation" class="mt-2">
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
              <label class="label mb-1" for="edit-collaborator-ids">Collaborators</label>
              <select
                id="edit-collaborator-ids"
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
              <.button class="btn btn-primary" phx-disable-with="Saving…">Save changes</.button>
            </div>
          </.form>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button type="button" phx-click="close_edit_modal">close</button>
        </form>
      </div>

      <div
        :if={@documents_modal_event}
        id={"document-modal-#{@documents_modal_event.id}"}
        class="modal modal-open"
      >
        <div class="modal-box max-w-2xl">
          <h3 class="font-bold text-lg">
            Documents — {humanize_status(@documents_modal_event.status)}
          </h3>
          <p class="text-sm text-base-content/60 mt-1">
            Files attached to this workflow step. Required slots are counted across all steps until marked done.
          </p>

          <section class="mt-5">
            <h4 class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
              Uploaded files
            </h4>
            <p :if={@documents_modal_event.documents == []} class="text-sm text-base-content/50 mt-2">
              No documents on this step yet.
            </p>
            <ul
              :if={@documents_modal_event.documents != []}
              id={"document-list-#{@documents_modal_event.id}"}
              class="mt-2 space-y-3"
            >
              <li
                :for={doc <- @documents_modal_event.documents}
                id={"doc-row-#{doc.id}"}
                class="rounded-lg border border-base-300 p-3 text-sm"
              >
                <div class="flex flex-wrap items-center justify-between gap-2">
                  <div class="flex items-center gap-2 min-w-0">
                    <.icon name="hero-paper-clip-mini" class="size-4 text-base-content/40 shrink-0" />
                    <.link
                      href={
                        ~p"/entities/#{@current_scope.entity.slug}/obligations/#{@obligation.id}/documents/#{doc.id}"
                      }
                      target="_blank"
                      class={[
                        "link link-hover truncate",
                        doc.voided_at && "line-through text-base-content/40"
                      ]}
                    >
                      {file_name(doc)}
                    </.link>
                    <span :if={doc.document_slot} class="badge badge-xs badge-ghost">
                      {doc.document_slot}
                    </span>
                    <span :if={doc.voided_at} class="badge badge-xs badge-error">voided</span>
                  </div>
                  <span class="text-xs text-base-content/50">
                    {format_datetime(doc.inserted_at)}
                  </span>
                </div>
                <p :if={doc.void_reason} class="text-xs text-base-content/50 mt-1">
                  Void reason: {doc.void_reason}
                </p>
                <div :if={@voiding_document_id != doc.id} class="mt-2">
                  <button
                    :if={Obligations.document_voidable?(@current_scope, @obligation, doc)}
                    id={"void-doc-#{doc.id}"}
                    type="button"
                    phx-click="void_document"
                    phx-value-document_id={doc.id}
                    class="btn btn-ghost btn-xs text-error"
                  >
                    Void
                  </button>
                </div>
                <.form
                  :if={@voiding_document_id == doc.id}
                  for={%{}}
                  id={"void-form-#{doc.id}"}
                  phx-submit="confirm_void_document"
                  class="mt-2 space-y-2"
                >
                  <input type="hidden" name="document_id" value={doc.id} />
                  <input type="hidden" name="event_id" value={@documents_modal_event.id} />
                  <.input
                    :if={@void_reason_required?}
                    name="reason"
                    type="text"
                    label="Reason for voiding"
                    required
                  />
                  <div class="flex gap-2">
                    <.button class="btn btn-error btn-sm" phx-disable-with="Voiding…">
                      Confirm void
                    </.button>
                    <button
                      type="button"
                      class="btn btn-ghost btn-sm"
                      phx-click="cancel_void_document"
                    >
                      Cancel
                    </button>
                  </div>
                </.form>
              </li>
            </ul>
          </section>

          <.obligation_document_upload_forms
            event={@documents_modal_event}
            required_docs={@required_docs}
            uploads={@uploads}
            uploadable?={event_uploadable?(@documents_modal_event, assigns)}
            upload_slot_target={@upload_slot_target}
          />

          <div class="modal-action">
            <button type="button" class="btn" phx-click="close_documents_modal">Close</button>
          </div>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button type="button" phx-click="close_documents_modal">close</button>
        </form>
      </div>

      <div
        :if={@show_done_modal}
        id="done-modal"
        class="modal modal-open"
      >
        <div class="modal-box">
          <h3 class="font-bold text-lg">Mark done</h3>
          <.form for={@done_form} id="done-form" phx-submit="complete">
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
              <.button class="btn btn-primary">Complete</.button>
            </div>
          </.form>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button type="button" phx-click="close_done_modal">close</button>
        </form>
      </div>

      <div :if={@show_cancel_modal} id="cancel-modal" class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Cancel obligation</h3>
          <p class="text-sm text-base-content/60 mt-1">
            This removes the obligation from active dashboards. A reason is recorded on the timeline.
          </p>
          <.form for={@cancel_form} id="cancel-form" phx-submit="confirm_cancel" class="mt-4">
            <.input
              field={@cancel_form[:note]}
              type="textarea"
              label="Reason for cancelling"
              required
            />
            <div class="modal-action">
              <button type="button" class="btn" phx-click="close_cancel_modal">Back</button>
              <.button class="btn btn-error" phx-disable-with="Cancelling…">Cancel obligation</.button>
            </div>
          </.form>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button type="button" phx-click="close_cancel_modal">close</button>
        </form>
      </div>

      <div :if={@show_end_series_modal} id="end-series-modal" class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">End series</h3>
          <p class="text-sm text-base-content/60 mt-1">
            Cancels the current cycle and stops future recurrence. A reason is recorded on the timeline.
          </p>
          <.form
            for={@end_series_form}
            id="end-series-form"
            phx-submit="confirm_end_series"
            class="mt-4"
          >
            <.input
              field={@end_series_form[:note]}
              type="textarea"
              label="Reason for ending series"
              required
            />
            <div class="modal-action">
              <button type="button" class="btn" phx-click="close_end_series_modal">Back</button>
              <.button class="btn btn-error" phx-disable-with="Ending…">End series</.button>
            </div>
          </.form>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button type="button" phx-click="close_end_series_modal">close</button>
        </form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    obligation =
      scope
      |> Obligations.get_obligation!(id)
      |> Map.update!(:events, fn events -> Enum.sort_by(events, & &1.inserted_at, DateTime) end)

    today = Urgency.today_for(scope.entity.timezone)

    urgency = Urgency.classify(obligation.obligation_type, obligation.due_by, today)
    live? = live_cycle?(obligation)

    {:ok,
     socket
     |> assign(:show_done_modal, false)
     |> assign(:show_cancel_modal, false)
     |> assign(:show_end_series_modal, false)
     |> assign(:show_edit_modal, false)
     |> assign(:documents_modal_event_id, nil)
     |> assign(:documents_modal_event, nil)
     |> assign(:upload_slot_target, nil)
     |> assign(:voiding_document_id, nil)
     |> assign(:show_corrections?, false)
     |> assign(:editing_note_id, nil)
     |> assign(:note_form, nil)
     |> assign(:recurring?, recurring?(obligation))
     |> assign(:today, today)
     |> assign(:urgency, urgency)
     |> assign(:live?, live?)
     |> assign(:member_options, member_options(scope))
     |> allow_upload(:document, accept: :any, max_entries: 1, max_file_size: 20_000_000)
     |> assign_obligation(obligation)
     |> assign_done_form(obligation)
     |> assign_cancel_form()
     |> assign_end_series_form()
     |> assign_edit_form(obligation)}
  end

  @impl true
  def handle_event("start_progress", _params, socket) do
    scope = socket.assigns.current_scope
    obligation = socket.assigns.obligation

    case Obligations.start_progress(scope, obligation) do
      {:ok, _} ->
        {:noreply, reload(socket) |> put_flash(:info, "Progress updated.")}

      {:error, :not_open} ->
        {:noreply, put_flash(socket, :error, "Already in progress.")}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  def handle_event("show_corrections", _params, socket) do
    {:noreply, assign(socket, :show_corrections?, true)}
  end

  def handle_event("hide_corrections", _params, socket) do
    {:noreply, assign(socket, :show_corrections?, false)}
  end

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

  def handle_event("open_done_modal", _params, socket) do
    {:noreply, assign(socket, :show_done_modal, true)}
  end

  def handle_event("close_done_modal", _params, socket) do
    {:noreply, assign(socket, :show_done_modal, false)}
  end

  def handle_event("complete", %{"done" => params}, socket) do
    scope = socket.assigns.current_scope
    obligation = socket.assigns.obligation

    attrs = %{
      note: params["note"],
      next_due_by: parse_date(params["next_due_by"])
    }

    case Obligations.complete(scope, obligation, attrs) do
      {:ok, _completed, _spawned} ->
        {:noreply,
         socket
         |> put_flash(:info, "Obligation completed.")
         |> push_navigate(to: ~p"/entities/#{scope.entity.slug}/obligations")}

      {:error, :next_due_required} ->
        {:noreply,
         put_flash(socket, :error, "Next due date is required for recurring obligations.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not complete obligation.")}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  def handle_event("open_cancel_modal", _params, socket) do
    {:noreply, socket |> assign(:show_cancel_modal, true) |> assign_cancel_form()}
  end

  def handle_event("close_cancel_modal", _params, socket) do
    {:noreply, assign(socket, :show_cancel_modal, false)}
  end

  def handle_event("confirm_cancel", %{"cancel" => %{"note" => note}}, socket) do
    scope = socket.assigns.current_scope

    case Obligations.cancel_obligation(scope, socket.assigns.obligation, %{note: note}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Obligation cancelled.")
         |> push_navigate(to: ~p"/entities/#{scope.entity.slug}/obligations")}

      {:error, :note_required} ->
        {:noreply, put_flash(socket, :error, "A reason is required.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not cancel.")}
    end
  end

  def handle_event("open_end_series_modal", _params, socket) do
    {:noreply, socket |> assign(:show_end_series_modal, true) |> assign_end_series_form()}
  end

  def handle_event("close_end_series_modal", _params, socket) do
    {:noreply, assign(socket, :show_end_series_modal, false)}
  end

  def handle_event("confirm_end_series", %{"end_series" => %{"note" => note}}, socket) do
    scope = socket.assigns.current_scope

    case Obligations.end_series(scope, socket.assigns.obligation, %{note: note}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Series ended.")
         |> push_navigate(to: ~p"/entities/#{scope.entity.slug}/obligations")}

      {:error, :note_required} ->
        {:noreply, put_flash(socket, :error, "A reason is required.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not end series.")}
    end
  end

  def handle_event("open_documents_modal", %{"event_id" => event_id}, socket) do
    case find_event(socket.assigns.obligation.events, event_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Event not found.")}

      event ->
        {:noreply,
         socket
         |> assign(:documents_modal_event_id, event.id)
         |> assign(:documents_modal_event, event)
         |> assign(:upload_slot_target, nil)}
    end
  end

  def handle_event("close_documents_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:documents_modal_event_id, nil)
     |> assign(:documents_modal_event, nil)
     |> assign(:upload_slot_target, nil)
     |> assign(:voiding_document_id, nil)}
  end

  def handle_event("select_upload_slot", %{"event_id" => event_id, "slot" => slot}, socket) do
    if socket.assigns.documents_modal_event_id == event_id or
         to_string(socket.assigns.documents_modal_event_id) == event_id do
      target = if slot == "additional", do: :additional, else: slot
      {:noreply, assign(socket, :upload_slot_target, target)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("clear_upload_slot", _params, socket) do
    {:noreply, assign(socket, :upload_slot_target, nil)}
  end

  def handle_event("void_document", %{"document_id" => document_id}, socket) do
    {:noreply, assign(socket, :voiding_document_id, document_id)}
  end

  def handle_event("cancel_void_document", _params, socket) do
    {:noreply, assign(socket, :voiding_document_id, nil)}
  end

  def handle_event("confirm_void_document", %{"document_id" => document_id} = params, socket) do
    scope = socket.assigns.current_scope
    obligation = socket.assigns.obligation
    reason = Map.get(params, "reason")
    event_id = Map.get(params, "event_id", socket.assigns.documents_modal_event_id)

    case find_event_document(socket.assigns.obligation.events, event_id, document_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Document not found.")}

      document ->
        case Obligations.void_document(scope, obligation, document, %{reason: reason}) do
          {:ok, _} ->
            {:noreply,
             socket
             |> reload()
             |> assign(:voiding_document_id, nil)
             |> assign(:upload_slot_target, nil)
             |> reopen_documents_modal(event_id)
             |> put_flash(:info, "Document voided.")}

          :not_authorise ->
            {:noreply, put_flash(socket, :error, "Not authorized to void this document.")}

          {:error, :reason_required} ->
            {:noreply, put_flash(socket, :error, "A reason is required to void this document.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not void document.")}
        end
    end
  end

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("add_document", %{"event_id" => event_id} = params, socket) do
    scope = socket.assigns.current_scope
    obligation = socket.assigns.obligation
    slot = blank_to_nil(params["document_slot"])

    case find_event(obligation.events, event_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Event not found.")}

      event ->
        results =
          consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
            upload = %Plug.Upload{
              path: path,
              filename: entry.client_name,
              content_type: entry.client_type
            }

            {:ok, Obligations.add_document(scope, obligation, event, upload, slot)}
          end)

        case results do
          [{:ok, _document}] ->
            {:noreply,
             socket
             |> reload()
             |> assign(:upload_slot_target, nil)
             |> reopen_documents_modal(event_id)
             |> put_flash(:info, "Document added.")}

          [:not_authorise] ->
            {:noreply, put_flash(socket, :error, "Not authorized.")}

          [{:error, _}] ->
            {:noreply, put_flash(socket, :error, "Could not add document.")}

          [] ->
            {:noreply, put_flash(socket, :error, "Choose a file to upload.")}
        end
    end
  end

  defp reload(socket) do
    scope = socket.assigns.current_scope
    obligation = Obligations.get_obligation!(scope, socket.assigns.obligation.id)
    assign_obligation(socket, obligation)
  end

  defp assign_obligation(socket, obligation) do
    doc_slots = parse_slots(obligation.complete_documents)
    satisfied = satisfied_slots(obligation)

    required_docs = Enum.map(doc_slots, fn slot -> {slot, MapSet.member?(satisfied, slot)} end)

    socket
    |> assign(:obligation, obligation)
    |> assign(:doc_slots, doc_slots)
    |> assign(:required_docs, required_docs)
    |> assign(:void_reason_required?, Obligations.document_void_reason_required?(obligation))
    |> assign(:series, Obligations.list_series(obligation.series_id))
    |> assign(:audit_logs, Obligations.list_audit_logs(obligation))
    |> assign(:can_add_document?, can_add_document?(socket.assigns.current_scope, obligation))
  end

  defp reopen_documents_modal(socket, nil), do: socket

  defp reopen_documents_modal(socket, event_id) do
    case find_event(socket.assigns.obligation.events, event_id) do
      nil ->
        assign(socket, :documents_modal_event, nil)

      event ->
        socket
        |> assign(:documents_modal_event_id, event.id)
        |> assign(:documents_modal_event, event)
    end
  end

  defp find_event_document(events, event_id, document_id) do
    case find_event(events, event_id) do
      nil ->
        nil

      event ->
        Enum.find(event.documents, &(to_string(&1.id) == to_string(document_id)))
    end
  end

  defp event_uploadable?(event, assigns) do
    assigns.live? and assigns.can_add_document? and event.status in ["open", "in_progress"]
  end

  defp find_event(events, event_id) do
    Enum.find(events, &(to_string(&1.id) == to_string(event_id)))
  end

  defp member_options(scope) do
    Entities.list_entity_members(scope.entity)
    |> Enum.map(fn {user, _membership} -> {user.email, user.id} end)
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

  defp cycle_marker(cycle, current_id) do
    {label, class} =
      cond do
        cycle.id == current_id -> {"Current", "badge-primary"}
        cycle.status == "cancelled" -> {"Cancelled", "badge-error"}
        match?(%DateTime{}, cycle.completed_at) -> {"Completed", "badge-success"}
        true -> {"Live", "badge-ghost"}
      end

    assigns = %{label: label, class: class}

    ~H"""
    <span class={["badge badge-sm", @class]}>{@label}</span>
    """
  end

  defp can_add_document?(scope, obligation) do
    Authorization.can?(scope, :edit_obligation) or
      Authorization.can?(scope, :start_progress, obligation)
  end

  defp satisfied_slots(obligation) do
    obligation.events
    |> Enum.flat_map(& &1.documents)
    |> Enum.reject(& &1.voided_at)
    |> Enum.map(& &1.document_slot)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp parse_slots(nil), do: []
  defp parse_slots(""), do: []

  defp parse_slots(csv) do
    csv
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp event_accent("done"), do: "border-success"
  defp event_accent("cancelled"), do: "border-error"
  defp event_accent("in_progress"), do: "border-warning"
  defp event_accent(_), do: "border-base-300"

  defp humanize_status("in_progress"), do: "In progress"
  defp humanize_status(status), do: String.capitalize(status)

  defp assign_done_form(socket, obligation) do
    suggestion =
      if socket.assigns.recurring? do
        Recurrence.next_due_suggestion(obligation.obligation_type, obligation.due_by)
      end

    assign(
      socket,
      :done_form,
      to_form(%{"note" => "", "next_due_by" => iso_date(suggestion)}, as: :done)
    )
  end

  defp assign_cancel_form(socket) do
    assign(socket, :cancel_form, to_form(%{"note" => ""}, as: :cancel))
  end

  defp assign_end_series_form(socket) do
    assign(socket, :end_series_form, to_form(%{"note" => ""}, as: :end_series))
  end

  defp recurring?(obligation) do
    Recurrence.recurring?(obligation.obligation_type) and is_nil(obligation.series_ended_at)
  end

  defp live_cycle?(%Obligation{status: "active", completed_at: nil}), do: true
  defp live_cycle?(_), do: false

  defp file_name(%{file: file}) when is_map(file) do
    Map.get(file, "original") || Map.get(file, :original) || "file"
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(slot), do: slot

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp iso_date(nil), do: ""
  defp iso_date(%Date{} = date), do: Date.to_iso8601(date)
end
