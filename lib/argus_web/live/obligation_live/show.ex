defmodule ArgusWeb.ObligationLive.Show do
  use ArgusWeb, :live_view
  use ArgusWeb.ObligationLive.DocumentEvents

  import ArgusWeb.ObligationCompletionDocuments
  import ArgusWeb.ObligationDocumentThumb
  import ArgusWeb.ObligationStepFiles

  alias ArgusWeb.ModalEscape
  alias ArgusWeb.ObligationLive.DocumentHelpers

  import ArgusWeb.ObligationLive.DocumentHelpers,
    only: [cycle_documents: 1, event_uploadable?: 2, parse_slots: 1, find_event: 2]

  alias ArgusWeb.ObligationLive.IndexHelpers, as: Index
  alias Argus.Authorization
  alias Argus.Entities
  alias Argus.Obligations
  alias Argus.Obligations.{Obligation, Recurrence, Urgency}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        id="obligation-show"
        class="space-y-3"
        phx-hook="UploadUiPersist"
        data-obligation-id={@obligation.id}
      >
        <section
          id="obligation-summary"
          class="argus-workbench w-[100%] mx-auto argus-obligation-summary"
        >
          <div
            id="obligation-meta"
            class="flex items-center justify-between text-sm text-base-content/70"
          >
            <div class="flex flex-wrap items-center gap-1.5 min-w-0">
              <span class="font-medium text-info">{@obligation.obligation_type.name}</span>
            </div>
            <div class="mt-2 flex flex-wrap items-center gap-1.5">
              <span
                :if={is_nil(@obligation.primary_assignee)}
                class="badge badge-sm badge-secondary badge-soft gap-1"
              >
                Unassigned
              </span>
              <span
                :if={@obligation.primary_assignee && other_collaborators(@obligation) == []}
                class="badge badge-sm badge-primary badge-soft gap-1"
              >
                <.icon name="hero-user-mini" class="size-3" />
                {@obligation.primary_assignee.email}
                <span class="text-[0.65rem] font-semibold uppercase tracking-wide opacity-70">
                  Primary
                </span>
              </span>
              <div
                :if={@obligation.primary_assignee && other_collaborators(@obligation) != []}
                id="assignees-dropdown"
                class="dropdown"
              >
                <div
                  tabindex="0"
                  role="button"
                  id="assignees-toggle"
                  class="badge badge-sm badge-primary badge-soft gap-1 cursor-pointer"
                >
                  <.icon name="hero-user-mini" class="size-3" />
                  {@obligation.primary_assignee.email}
                  <span class="text-[0.65rem] font-semibold uppercase tracking-wide opacity-70">
                    Primary
                  </span>
                  <.icon name="hero-chevron-down-mini" class="size-3" />
                </div>
                <ul
                  tabindex="0"
                  class="dropdown-content menu menu-sm bg-base-100 rounded-box z-10 w-64 p-2 shadow border border-base-300"
                >
                  <li class="menu-title text-xs">Also collaborating</li>
                  <li :for={c <- other_collaborators(@obligation)}>
                    <span class="flex items-center gap-1">
                      <.icon name="hero-user-group-mini" class="size-3" />
                      {c.user.email}
                    </span>
                  </li>
                </ul>
              </div>
            </div>
            <div :if={@obligation.due_by} class="flex flex-wrap items-center gap-1.5 min-w-0 text-xs">
              <span class="argus-meta-label">Due</span>
              <span class="font-medium text-base-content">{format_date(@obligation.due_by)}</span>
              <span :if={@cycle_status == :skipped} class="text-base-content/60">· skipped</span>
            </div>
          </div>
          <div class="flex flex-wrap items-center justify-between gap-x-2 gap-y-1 mt-2">
            <h1 class="text-lg font-semibold leading-tight min-w-0">{@obligation.title}</h1>
            <div class="flex">
              <.urgency_badge
                :if={@live? and @obligation.due_by}
                tier={@tier}
                due_by={@obligation.due_by}
                today={@today}
              />
              <.obligation_status_badge
                :if={!@live?}
                cycle_status={@cycle_status}
                in_error={!is_nil(@obligation.completed_in_error_at)}
                obligation={@obligation}
              />
              <div :if={@correctable?} class="dropdown dropdown-end">
                <div
                  tabindex="0"
                  role="button"
                  id="completed-actions-menu"
                  class="btn btn-ghost btn-xs px-1"
                  aria-label="Completed cycle actions"
                >
                  <.icon name="hero-ellipsis-vertical-mini" class="size-4" />
                </div>
                <ul
                  tabindex="0"
                  class="dropdown-content menu menu-sm bg-base-100 rounded-box z-10 w-60 p-2 shadow border border-base-300"
                >
                  <li>
                    <button
                      id="mark-error-btn"
                      type="button"
                      phx-click="open_correct_modal"
                      class="text-warning"
                    >
                      <.icon name="hero-exclamation-triangle-mini" class="size-4" />
                      Mark completed in error
                    </button>
                  </li>
                </ul>
              </div>
            </div>
          </div>
          <div
            :if={@required_docs != []}
            id="completion-summary"
            class={ArgusWeb.ObligationDocumentThumb.thumb_grid_classes(:desktop)}
          >
            <%= for {slot, live} <- @required_docs do %>
              <%= if live do %>
                <.doc_thumb_tile
                  id={"summary-slot-#{slot}"}
                  manage_id={"open-completion-slot-#{slot}"}
                  href={doc_href(@current_scope.entity.slug, @obligation, live)}
                  name={file_name(live)}
                  label={slot}
                />
              <% else %>
                <.doc_thumb_tile
                  id={"summary-slot-#{slot}"}
                  manage_id={"open-completion-slot-#{slot}"}
                  label={slot}
                  empty?={true}
                />
              <% end %>
            <% end %>
          </div>
          <div
            :if={@live?}
            id="obligation-actions"
            class="mt-3 pt-3 border-t border-base-300 flex flex-wrap items-center gap-x-4 gap-y-2 w-full"
          >
            <div id="obligation-progress-actions" class="argus-inline-actions">
              <button
                :if={@live? and Authorization.can?(@current_scope, :edit_obligation)}
                id="edit-obligation-btn"
                type="button"
                phx-click="open_edit_modal"
                class="btn btn-outline btn-sm gap-1"
              >
                <.icon name="hero-pencil-square-mini" class="size-3.5" /> Edit
              </button>
              <button
                :if={@live? and Authorization.can?(@current_scope, :start_progress, @obligation)}
                id="start-progress-btn"
                type="button"
                phx-click="open_progress_modal"
                class="btn btn-success btn-sm"
              >
                Update progress
              </button>
            </div>
            <div
              id="obligation-done-actions"
              class="argus-inline-actions flex-1 flex justify-center min-w-[6rem]"
            >
              <button
                :if={@docs_complete? and Authorization.can?(@current_scope, :mark_done, @obligation)}
                id="done-btn"
                type="button"
                phx-click="open_done_modal"
                class="btn btn-primary btn-sm"
              >
                Mark done
              </button>
            </div>
            <div id="obligation-series-actions" class="argus-inline-actions ml-auto">
              <button
                :if={Authorization.can?(@current_scope, :skip)}
                id="skip-btn"
                type="button"
                phx-click="open_skip_modal"
                class="btn btn-outline btn-warning btn-sm"
              >
                Skip
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
            </div>
          </div>

          <div
            :if={@obligation.completed_in_error_at}
            id="completed-in-error-banner"
            class="mt-3 rounded-box border border-warning/40 bg-warning/10 px-3 py-2 text-sm flex flex-wrap items-center gap-2"
          >
            <.icon name="hero-exclamation-triangle-mini" class="size-4 text-warning shrink-0" />
            <span class="font-medium">Completed in error.</span>
            <span class="text-base-content/70">{@obligation.completed_in_error_reason}</span>
            <.link
              :if={@obligation.replaced_by_id}
              navigate={
                ~p"/entities/#{@current_scope.entity.slug}/obligations/#{@obligation.replaced_by_id}"
              }
              class="link link-primary ml-auto"
            >
              View replacement
            </.link>
          </div>

          <div
            :if={@obligation.replaces_id}
            id="replaces-banner"
            class="mt-3 rounded-box border border-base-300 bg-base-200/40 px-3 py-2 text-sm flex flex-wrap items-center gap-2"
          >
            <.icon name="hero-arrow-uturn-left-mini" class="size-4 text-base-content/50 shrink-0" />
            <span class="text-base-content/70">Replacement for a cycle completed in error.</span>
            <.link
              navigate={
                ~p"/entities/#{@current_scope.entity.slug}/obligations/#{@obligation.replaces_id}"
              }
              class="link link-primary ml-auto"
            >
              View original
            </.link>
          </div>
        </section>

        <section class="argus-section">
          <ol id="event-timeline">
            <li
              :for={event <- @obligation.events}
              id={"event-#{event.id}"}
              data-status={event.status}
              class={["argus-event-row border-l-4", event_accent(event.status)]}
            >
              <div class="argus-event-head">
                <span class="font-semibold text-sm">{humanize_status(event.status)}</span>
                <span class="text-xs text-base-content/50">{format_datetime(event.inserted_at)}</span>
                <span :if={event.status_by} class="text-xs text-base-content/50">
                  · {event.status_by.email}
                </span>
                <button
                  id={"step-files-btn-#{event.id}"}
                  type="button"
                  phx-click="open_step_files"
                  phx-value-event_id={event.id}
                  class="btn btn-ghost btn-xs h-6 min-h-6 px-1.5 gap-1 ml-auto"
                >
                  <.icon name="hero-paper-clip-mini" class="size-3.5" />
                  Files ({length(other_file_count(event, @doc_slots))})
                </button>
              </div>
              <div
                :if={@editing_note_id != event.id}
                id={"event-note-#{event.id}"}
                class="argus-event-note-block relative"
              >
                <div :if={is_binary(event.note)} class="argus-event-note">{event.note}</div>
                <div :if={is_nil(event.note)} class="argus-event-note argus-event-note-empty">
                  No note added
                </div>
                <button
                  :if={Obligations.note_editable?(@current_scope, event, @obligation)}
                  id={"edit-note-#{event.id}"}
                  type="button"
                  phx-click="edit_note"
                  phx-value-event_id={event.id}
                  class="btn btn-ghost btn-xs btn-square absolute bottom-2 right-2 bg-base-100/80"
                  aria-label="Edit note"
                >
                  <.icon name="hero-pencil-square-mini" class="size-4" />
                </button>
              </div>
              <.form
                :if={@editing_note_id == event.id}
                for={@note_form}
                id={"note-form-#{event.id}"}
                phx-submit="save_note"
                class="argus-event-note-block"
              >
                <input type="hidden" name="event_id" value={event.id} />
                <div class="relative">
                  <textarea name="note[note]" rows="5" class="textarea w-full pb-12">{Phoenix.HTML.Form.normalize_value("textarea", @note_form[:note].value)}</textarea>
                  <div class="absolute bottom-2 right-2 flex gap-2">
                    <button type="button" class="btn btn-warning btn-sm" phx-click="cancel_note_edit">
                      Cancel
                    </button>
                    <.button class="btn btn-success btn-sm" phx-disable-with="Saving…">Save</.button>
                  </div>
                </div>
              </.form>
              <div
                :if={timeline_files(event, @doc_slots) != []}
                id={"event-files-#{event.id}"}
                class={ArgusWeb.ObligationDocumentThumb.thumb_grid_classes(:desktop)}
              >
                <.doc_thumb_preview
                  :for={doc <- timeline_files(event, @doc_slots)}
                  id={"event-file-#{doc.id}"}
                  href={doc_href(@current_scope.entity.slug, @obligation, doc)}
                  name={file_name(doc)}
                  label={file_name(doc)}
                />
              </div>
            </li>
          </ol>
        </section>

        <div :if={@audit_logs != []} class="mt-3">
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
      </div>

      <div :if={@show_edit_modal} id="edit-modal" class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Edit duty</h3>
          <.form
            for={@edit_form}
            id="edit-obligation-form"
            phx-change="validate_edit"
            phx-submit="save_obligation"
            class="mt-2"
          >
            <.char_count_input field={@edit_form[:title]} label="Title" max={60} required />
            <.input field={@edit_form[:someday]} type="checkbox" label="No due date (Someday)" />
            <.input
              :if={!someday?(@edit_form)}
              field={@edit_form[:due_by]}
              type="date"
              label="Due by"
              required
            />
            <div class="fieldset mb-2">
              <.input
                field={@edit_form[:primary_assignee_id]}
                type="select"
                label="Primary assignee"
                options={@member_options}
                prompt="Unassigned"
              />
              <label class="label mb-1 mt-2" for="edit-collaborator-ids">Also collaborating</label>
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
                Hold ⌘/Ctrl to select more than one. Deselect all to remove additional collaborators.
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

      <div :if={@show_completion_modal} id="completion-modal" class="modal modal-open">
        <div class="modal-box max-w-lg">
          <h3 class="font-bold text-lg">
            {if @active_completion_slot,
              do: "Completion document: #{@active_completion_slot}",
              else: "Completion documents"}
          </h3>
          <div class="mt-3">
            <.completion_documents
              obligation={@obligation}
              current_scope={@current_scope}
              entity_slug={@current_scope.entity.slug}
              documents={cycle_documents(@obligation)}
              required_slots={DocumentHelpers.scoped_slots(@doc_slots, @active_completion_slot)}
              uploadable?={@can_add_document? and @live?}
              voiding_document_id={@voiding_document_id}
              deleting_document_id={@deleting_document_id}
              void_reason_required?={@void_reason_required?}
            />
          </div>
          <div class="modal-action mt-2">
            <button
              id="close-completion-modal"
              type="button"
              class="btn"
              phx-click="close_completion_modal"
            >Close</button>
          </div>
        </div>
        <div class="modal-backdrop" aria-hidden="true"></div>
      </div>

      <div :if={@show_correct_modal} id="correct-modal" class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Mark completed in error</h3>
          <p class="text-sm text-base-content/60 mt-1">
            This keeps the completed cycle for audit and creates a fresh one-off replacement
            to redo the work. A recurring series is not affected.
          </p>
          <.form for={%{}} id="correct-form" phx-submit="confirm_correct" class="mt-4 space-y-3">
            <.input
              name="correct[reason]"
              value=""
              type="textarea"
              label="Reason (required)"
              required
            />
            <.input
              name="correct[replacement_due_by]"
              value={@obligation.due_by && Date.to_iso8601(@obligation.due_by)}
              type="date"
              label="Replacement due date"
            />
            <div class="modal-action">
              <button type="button" class="btn" phx-click="close_correct_modal">Cancel</button>
              <.button class="btn btn-warning" phx-disable-with="Working…">
                Mark in error &amp; create replacement
              </.button>
            </div>
          </.form>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button type="button" phx-click="close_correct_modal">close</button>
        </form>
      </div>

      <div
        :if={@step_files_modal_event}
        id={"step-files-modal-#{@step_files_modal_event.id}"}
        class="modal modal-open"
      >
        <div class="modal-box max-w-lg">
          <h3 class="font-bold text-lg">Files — {humanize_status(@step_files_modal_event.status)}</h3>
          <div class="mt-3">
            <.step_files
              event={@step_files_modal_event}
              obligation={@obligation}
              current_scope={@current_scope}
              entity_slug={@current_scope.entity.slug}
              required_slots={@doc_slots}
              uploadable?={event_uploadable?(@step_files_modal_event, assigns)}
              voiding_document_id={@voiding_document_id}
              deleting_document_id={@deleting_document_id}
              void_reason_required?={@void_reason_required?}
            />
          </div>
          <div class="modal-action mt-2">
            <button type="button" class="btn" phx-click="close_step_files">Close</button>
          </div>
        </div>
        <div class="modal-backdrop" aria-hidden="true"></div>
      </div>

      <div
        :if={@show_done_modal}
        id="done-modal"
        class="modal modal-open"
      >
        <div class="modal-box">
          <h3 class="font-bold text-lg">Mark done</h3>
          <.form for={@done_form} id="done-form" phx-submit="complete" class="space-y-3">
            <.done_document_checklist
              required_docs={@required_docs}
              can_upload?={@can_add_document?}
            />
            <.input
              :if={@recurring?}
              field={@done_form[:next_due_by]}
              type="date"
              label="Next due date"
              required
            />
            <.input field={@done_form[:note]} type="textarea" label="Completion note" required />
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

      <div :if={@show_progress_modal} id="progress-modal" class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Update progress</h3>
          <p class="text-sm text-base-content/60 mt-1">
            Record what changed — this note is added to the timeline.
          </p>
          <.form
            for={@progress_form}
            id="progress-form"
            phx-submit="confirm_start_progress"
            class="mt-4"
          >
            <.input
              field={@progress_form[:note]}
              type="textarea"
              label="Progress note"
              required
            />
            <div class="modal-action">
              <button type="button" class="btn" phx-click="close_progress_modal">Back</button>
              <.button class="btn btn-primary" phx-disable-with="Saving…">Update progress</.button>
            </div>
          </.form>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button type="button" phx-click="close_progress_modal">close</button>
        </form>
      </div>

      <div :if={@show_skip_modal} id="skip-modal" class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Skip this cycle</h3>
          <p class="text-sm text-base-content/60 mt-1">
            Closes this cycle without completing it. A reason is recorded on the timeline.
          </p>
          <.form for={@skip_form} id="skip-form" phx-submit="skip" class="mt-4">
            <.input
              :if={@recurring?}
              field={@skip_form[:next_due_by]}
              type="date"
              label="Next due date"
              required
            />
            <.input
              field={@skip_form[:note]}
              type="textarea"
              label="Reason for skipping"
              required
            />
            <div class="modal-action">
              <button type="button" class="btn" phx-click="close_skip_modal">Back</button>
              <.button class="btn btn-warning" phx-disable-with="Skipping…">Skip</.button>
            </div>
          </.form>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button type="button" phx-click="close_skip_modal">close</button>
        </form>
      </div>

      <div :if={@show_end_series_modal} id="end-series-modal" class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">End series</h3>
          <p class="text-sm text-base-content/60 mt-1">
            Closes the current cycle and stops future recurrence. A reason is recorded on the timeline.
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

    tier = Urgency.tier(obligation.obligation_type, obligation.due_by, today)
    live? = live_cycle?(obligation)

    {:ok,
     socket
     |> assign(:show_done_modal, false)
     |> assign(:show_progress_modal, false)
     |> assign(:show_skip_modal, false)
     |> assign(:show_end_series_modal, false)
     |> assign(:show_edit_modal, false)
     |> assign(:show_completion_modal, false)
     |> assign(:active_completion_slot, nil)
     |> assign(:show_correct_modal, false)
     |> assign(:step_files_modal_event_id, nil)
     |> assign(:step_files_modal_event, nil)
     |> assign(:voiding_document_id, nil)
     |> assign(:deleting_document_id, nil)
     |> assign(:show_corrections?, false)
     |> assign(:editing_note_id, nil)
     |> assign(:note_form, nil)
     |> assign(:recurring?, recurring?(obligation))
     |> assign(:today, today)
     |> assign(:tier, tier)
     |> assign(:cycle_status, Index.cycle_status(obligation))
     |> assign(:live?, live?)
     |> assign(:member_options, member_options(scope))
     |> assign_obligation(obligation)
     |> assign_done_form(obligation)
     |> assign_progress_form()
     |> assign_skip_form(obligation)
     |> assign_end_series_form()
     |> assign_edit_form(obligation)}
  end

  @impl true
  def handle_event("close_modal_on_escape", _params, socket) do
    {:noreply, ModalEscape.close_obligation_modals(socket)}
  end

  def handle_event("open_progress_modal", _params, socket) do
    {:noreply, socket |> assign(:show_progress_modal, true) |> assign_progress_form()}
  end

  def handle_event("close_progress_modal", _params, socket) do
    {:noreply, assign(socket, :show_progress_modal, false)}
  end

  def handle_event("confirm_start_progress", %{"progress" => %{"note" => note}}, socket) do
    scope = socket.assigns.current_scope
    obligation = socket.assigns.obligation

    case Obligations.start_progress(scope, obligation, %{note: note}) do
      {:ok, _} ->
        {:noreply,
         reload(socket)
         |> assign(:show_progress_modal, false)
         |> put_flash(:info, "Progress updated.")}

      {:error, :not_live} ->
        {:noreply, put_flash(socket, :error, "This cycle is closed.")}

      {:error, :note_required} ->
        {:noreply, put_flash(socket, :error, "A progress note is required.")}

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

  def handle_event("validate_edit", %{"obligation" => params}, socket) do
    form =
      to_form(
        %{
          "title" => params["title"],
          "someday" => params["someday"],
          "due_by" => params["due_by"],
          "primary_assignee_id" => params["primary_assignee_id"]
        },
        as: "obligation"
      )

    {:noreply, assign(socket, :edit_form, form)}
  end

  def handle_event("save_obligation", %{"obligation" => params}, socket) do
    scope = socket.assigns.current_scope
    obligation = socket.assigns.obligation

    attrs = %{
      title: params["title"],
      someday: params["someday"],
      due_by: parse_date(params["due_by"]),
      primary_assignee_id: normalize_assignee(params["primary_assignee_id"])
    }

    collaborator_ids = parse_collaborator_ids(params["collaborator_ids"])

    case Obligations.update_obligation(scope, obligation, attrs) do
      {:ok, updated} ->
        case Obligations.update_collaborators(scope, updated, collaborator_ids) do
          {:ok, _} ->
            {:noreply,
             reload(socket)
             |> assign(:show_edit_modal, false)
             |> put_flash(:info, "Duty updated.")}

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
         |> put_flash(:info, "Duty completed.")
         |> push_navigate(to: ~p"/entities/#{scope.entity.slug}")}

      {:error, :next_due_required} ->
        {:noreply,
         put_flash(socket, :error, "Next due date is required for recurring obligations.")}

      {:error, :note_required} ->
        {:noreply, put_flash(socket, :error, "A completion note is required.")}

      {:error, {:missing_document, slot}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Missing required document: #{slot}. Upload it before completing."
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not complete obligation.")}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  def handle_event("open_skip_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_skip_modal, true)
     |> assign_skip_form(socket.assigns.obligation)}
  end

  def handle_event("close_skip_modal", _params, socket) do
    {:noreply, assign(socket, :show_skip_modal, false)}
  end

  def handle_event("skip", %{"skip" => params}, socket) do
    scope = socket.assigns.current_scope

    attrs = %{
      note: params["note"],
      next_due_by: parse_date(params["next_due_by"])
    }

    case Obligations.skip(scope, socket.assigns.obligation, attrs) do
      {:ok, _cancelled, _spawned} ->
        {:noreply,
         socket
         |> put_flash(:info, "Cycle skipped.")
         |> push_navigate(to: ~p"/entities/#{scope.entity.slug}")}

      {:error, :next_due_required} ->
        {:noreply,
         put_flash(socket, :error, "Next due date is required for recurring obligations.")}

      {:error, :note_required} ->
        {:noreply, put_flash(socket, :error, "A reason is required.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not skip cycle.")}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}
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
         |> push_navigate(to: ~p"/entities/#{scope.entity.slug}")}

      {:error, :note_required} ->
        {:noreply, put_flash(socket, :error, "A reason is required.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not end series.")}
    end
  end

  def handle_event("open_correct_modal", _params, socket) do
    {:noreply, assign(socket, :show_correct_modal, true)}
  end

  def handle_event("close_correct_modal", _params, socket) do
    {:noreply, assign(socket, :show_correct_modal, false)}
  end

  def handle_event("confirm_correct", %{"correct" => params}, socket) do
    scope = socket.assigns.current_scope
    obligation = socket.assigns.obligation

    attrs = %{
      reason: params["reason"],
      replacement_due_by: params["replacement_due_by"]
    }

    case Obligations.mark_completed_in_error(scope, obligation, attrs) do
      {:ok, _original, replacement} ->
        {:noreply,
         socket
         |> put_flash(:info, "Cycle marked in error. Replacement created.")
         |> push_navigate(to: ~p"/entities/#{scope.entity.slug}/obligations/#{replacement.id}")}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}

      {:error, :note_required} ->
        {:noreply, put_flash(socket, :error, "A reason is required.")}

      {:error, reason} when reason in [:not_correctable, :already_corrected] ->
        {:noreply,
         socket
         |> assign(:show_correct_modal, false)
         |> put_flash(:error, "This cycle can no longer be corrected.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not mark in error.")}
    end
  end

  defp other_file_count(event, required_slots) do
    {live_other, _voided} = DocumentHelpers.step_files(event.documents, required_slots)
    live_other
  end

  # Files shown inline under a timeline event: that event's own supporting
  # (non-required-slot) files. Required completion files live in the summary,
  # beside the slot badges — never in the timeline.
  defp timeline_files(event, required_slots) do
    {supporting, _voided} = DocumentHelpers.step_files(event.documents, required_slots)
    supporting
  end

  defp reload(socket) do
    scope = socket.assigns.current_scope
    obligation = Obligations.get_obligation!(scope, socket.assigns.obligation.id)

    socket = assign_obligation(socket, obligation)

    case socket.assigns.step_files_modal_event_id do
      nil ->
        socket

      event_id ->
        assign(socket, :step_files_modal_event, find_event(obligation.events, event_id))
    end
  end

  defp assign_obligation(socket, obligation) do
    doc_slots = parse_slots(obligation.complete_documents)

    {slot_rows, _voided} =
      DocumentHelpers.completion_view(cycle_documents(obligation), doc_slots)

    scope = socket.assigns.current_scope

    socket
    |> assign(:obligation, obligation)
    |> assign(:doc_slots, doc_slots)
    |> assign(:required_docs, slot_rows)
    |> assign(:docs_complete?, Enum.all?(slot_rows, fn {_slot, live} -> live end))
    |> assign(:void_reason_required?, Obligations.document_void_reason_required?(obligation))
    |> assign(:audit_logs, Obligations.list_audit_logs(obligation))
    |> assign(:can_add_document?, can_add_document?(scope, obligation))
    |> assign(
      :correctable?,
      Index.cycle_status(obligation) == :completed and
        is_nil(obligation.completed_in_error_at) and
        Authorization.can?(socket.assigns.current_scope, :mark_completed_in_error)
    )
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
          "someday" => is_nil(obligation.due_by),
          "due_by" => iso_date(obligation.due_by),
          "primary_assignee_id" => obligation.primary_assignee_id
        },
        as: "obligation"
      )
    )
  end

  defp someday?(form), do: form[:someday].value in [true, "true"]

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

  defp can_add_document?(scope, obligation) do
    Authorization.can?(scope, :edit_obligation) or
      Authorization.can?(scope, :start_progress, obligation)
  end

  defp event_accent("done"), do: "border-success"
  defp event_accent("skipped"), do: "border-warning"
  defp event_accent("series_ended"), do: "border-neutral"
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

  defp assign_progress_form(socket) do
    assign(socket, :progress_form, to_form(%{"note" => ""}, as: :progress))
  end

  defp assign_skip_form(socket, obligation) do
    suggestion =
      Recurrence.next_due_suggestion(obligation.obligation_type, obligation.due_by)

    assign(
      socket,
      :skip_form,
      to_form(%{"note" => "", "next_due_by" => iso_date(suggestion)}, as: :skip)
    )
  end

  defp assign_end_series_form(socket) do
    assign(socket, :end_series_form, to_form(%{"note" => ""}, as: :end_series))
  end

  defp recurring?(obligation) do
    Recurrence.recurring?(obligation.obligation_type) and is_nil(obligation.series_ended_at)
  end

  defp live_cycle?(%Obligation{completed_at: nil, closed_at: nil}), do: true
  defp live_cycle?(_), do: false

  defp doc_href(entity_slug, obligation, doc) do
    ~p"/entities/#{entity_slug}/obligations/#{obligation.id}/documents/#{doc.id}"
  end

  defp file_name(%{file: file}) when is_map(file) do
    Map.get(file, "original") || Map.get(file, :original) || "file"
  end

  defp other_collaborators(%{primary_assignee: nil, collaborators: collaborators}),
    do: collaborators

  defp other_collaborators(%{primary_assignee: assignee, collaborators: collaborators}) do
    Enum.reject(collaborators, &(&1.user_id == assignee.id))
  end

  defp normalize_assignee(id), do: blank_to_nil(id)

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
