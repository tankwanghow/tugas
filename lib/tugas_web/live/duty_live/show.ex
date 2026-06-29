defmodule TugasWeb.DutyLive.Show do
  use TugasWeb, :live_view
  use TugasWeb.DutyLive.DocumentEvents

  import TugasWeb.DutyCompletionDocuments
  import TugasWeb.DutyDocumentThumb
  import TugasWeb.DutyStepFiles

  alias TugasWeb.ModalEscape
  alias TugasWeb.DutyLive.DocumentHelpers

  import TugasWeb.DutyLive.DocumentHelpers,
    only: [cycle_documents: 1, event_uploadable?: 2, parse_slots: 1, find_event: 2]

  alias TugasWeb.DutyLive.IndexHelpers, as: Index
  alias Tugas.Authorization
  alias Tugas.Entities
  alias Tugas.Duties
  alias Tugas.Duties.{Duty, Recurrence, Urgency}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        id="duty-show"
        class="space-y-3"
        phx-hook="UploadUiPersist"
        data-duty-id={@duty.id}
      >
        <.duty_series_nav
          id="duty-series-nav"
          entity_slug={@current_scope.entity.slug}
          variant={:desktop}
          previous={@series_previous}
          next={@series_next}
        />
        <section
          id="duty-summary"
          class="tugas-workbench w-[100%] mx-auto tugas-duty-summary"
        >
          <div
            id="duty-meta"
            class="flex items-center justify-between text-sm text-base-content/70"
          >
            <div class="flex flex-wrap items-center gap-1.5 min-w-0">
              <span class="font-medium text-info">{@duty.duty_type.name}</span>
            </div>
            <div class="flex flex-wrap items-center gap-1.5">
              <span
                :if={is_nil(@duty.primary_assignee)}
                class="badge badge-sm badge-secondary badge-soft gap-1"
              >
                Unassigned
              </span>
              <span
                :if={@duty.primary_assignee && other_collaborators(@duty) == []}
                class="badge badge-sm badge-primary badge-soft gap-1"
              >
                <.icon name="hero-user-mini" class="size-3" />
                {user_label(@duty.primary_assignee)}
                <span class="text-[0.65rem] font-semibold uppercase tracking-wide opacity-70">
                  Primary
                </span>
              </span>
              <div
                :if={@duty.primary_assignee && other_collaborators(@duty) != []}
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
                  {user_label(@duty.primary_assignee)}
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
                  <li :for={c <- other_collaborators(@duty)}>
                    <span class="flex items-center gap-1">
                      <.icon name="hero-user-group-mini" class="size-3" />
                      {user_label(c.user)}
                    </span>
                  </li>
                </ul>
              </div>
            </div>
            <div :if={@duty.due_by} class="flex flex-wrap items-center gap-1.5 min-w-0 text-xs">
              <span class="tugas-meta-label">Due</span>
              <span class="font-medium text-base-content">{format_date(@duty.due_by)}</span>
              <%!-- <span :if={@cycle_status == :skipped} class="text-base-content/60">· skipped</span> --%>
            </div>
            <div :if={is_nil(@duty.due_by)} class="font-medium text-base-content">
              <span class="text-success">No Due Date</span>
            </div>
          </div>
          <div class="flex flex-wrap items-center justify-between gap-x-2 gap-y-1 mt-2">
            <h1 class="font-semibold leading-tight min-w-0">{@duty.title}</h1>
            <div class="flex">
              <.cycle_badge
                cycle_status={@cycle_status}
                tier={@tier}
                duty={@duty}
                today={@today}
                timezone={@current_scope.entity.timezone}
                in_error={!is_nil(@duty.completed_in_error_at)}
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
            class={TugasWeb.DutyDocumentThumb.thumb_grid_classes(:desktop)}
          >
            <%= for {slot, live} <- @required_docs do %>
              <%= if live do %>
                <.doc_thumb_tile
                  id={"summary-slot-#{slot}"}
                  manage_id={"open-completion-slot-#{slot}"}
                  href={doc_href(@current_scope.entity.slug, @duty, live)}
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
            id="duty-actions"
            class="mt-3 pt-3 border-t border-base-300 flex flex-wrap items-center gap-x-4 gap-y-2 w-full"
          >
            <div id="duty-progress-actions" class="tugas-inline-actions">
              <button
                :if={@live? and Authorization.can?(@current_scope, :edit_duty)}
                id="edit-duty-btn"
                type="button"
                phx-click="open_edit_modal"
                class="btn btn-outline btn-sm gap-1"
              >
                <.icon name="hero-pencil-square-mini" class="size-3.5" /> Edit
              </button>
              <button
                :if={@live? and Authorization.can?(@current_scope, :start_progress, @duty)}
                id="start-progress-btn"
                type="button"
                phx-click="open_progress_modal"
                class="btn btn-success btn-sm"
              >
                <.icon name="hero-arrow-right" class="size-5" />Update progress
              </button>
            </div>
            <div
              id="duty-done-actions"
              class="tugas-inline-actions flex-1 flex justify-center min-w-[6rem]"
            >
              <button
                :if={@docs_complete? and Authorization.can?(@current_scope, :mark_done, @duty)}
                id="done-btn"
                type="button"
                phx-click="open_done_modal"
                class="btn btn-primary btn-sm"
              >
                <.icon name="hero-check-mini" class="size-5" />Mark done
              </button>
            </div>
            <div id="duty-series-actions" class="tugas-inline-actions ml-auto">
              <button
                :if={Authorization.can?(@current_scope, :skip)}
                id="skip-btn"
                type="button"
                phx-click="open_skip_modal"
                class="btn btn-outline btn-warning btn-sm"
              >
                <.icon name="hero-arrow-uturn-right" class="size-5" />Skip
              </button>
              <button
                :if={Authorization.can?(@current_scope, :end_series)}
                id="end-series-btn"
                type="button"
                phx-click="open_end_series_modal"
                class="btn btn-outline btn-sm"
              >
                <.icon name="hero-no-symbol" class="size-5" />End series
              </button>
            </div>
          </div>

          <div
            :if={@duty.completed_in_error_at}
            id="completed-in-error-banner"
            class="mt-3 rounded-box border border-warning/40 bg-warning/10 px-3 py-2 text-sm flex flex-wrap items-center gap-2"
          >
            <.icon name="hero-exclamation-triangle-mini" class="size-4 text-warning shrink-0" />
            <span class="font-medium">Completed in error.</span>
            <span class="text-base-content/70">{@duty.completed_in_error_reason}</span>
            <.link
              :if={@duty.replaced_by_id}
              navigate={~p"/entities/#{@current_scope.entity.slug}/duties/#{@duty.replaced_by_id}"}
              class="link link-primary ml-auto"
            >
              View replacement
            </.link>
          </div>

          <div
            :if={@duty.replaces_id}
            id="replaces-banner"
            class="mt-3 rounded-box border border-base-300 bg-base-200/40 px-3 py-2 text-sm flex flex-wrap items-center gap-2"
          >
            <.icon name="hero-arrow-uturn-left-mini" class="size-4 text-base-content/50 shrink-0" />
            <span class="text-base-content/70">Replacement for a cycle completed in error.</span>
            <.link
              navigate={~p"/entities/#{@current_scope.entity.slug}/duties/#{@duty.replaces_id}"}
              class="link link-primary ml-auto"
            >
              View original
            </.link>
          </div>
        </section>

        <section class="tugas-section">
          <ol id="event-timeline">
            <li
              :for={event <- @duty.events}
              id={"event-#{event.id}"}
              data-status={event.status}
              class={["tugas-event-row border-l-4", event_accent(event.status)]}
            >
              <div class="tugas-event-head">
                <span class="font-semibold text-sm">{humanize_status(event.status)}</span>
                <span class="text-xs text-base-content/50">{format_datetime(
                  event.inserted_at,
                  @current_scope.entity.timezone
                )}</span>
                <span :if={event.status_by} class="text-xs text-base-content/80">
                  {user_label(event.status_by)}
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
                class="tugas-event-note-block relative"
              >
                <div :if={is_binary(event.note)} class="tugas-event-note">{event.note}</div>
                <button
                  :if={Duties.note_editable?(@current_scope, event, @duty)}
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
                class="tugas-event-note-block"
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
                class={TugasWeb.DutyDocumentThumb.thumb_grid_classes(:desktop)}
              >
                <.doc_thumb_preview
                  :for={doc <- timeline_files(event, @doc_slots)}
                  id={"event-file-#{doc.id}"}
                  href={doc_href(@current_scope.entity.slug, @duty, doc)}
                  name={file_name(doc)}
                  label={file_name(doc)}
                />
              </div>
            </li>
          </ol>
        </section>

        <div :if={@audit_logs != []} class="mt-3">
          <button
            id="show-corrections-btn"
            type="button"
            phx-click="toggle_corrections"
            class="btn btn-ghost btn-sm"
          >
            <.icon name="hero-clipboard-document-list-mini" class="size-4" />
            {if @show_corrections?,
              do: "Hide corrections",
              else: "Show corrections (#{length(@audit_logs)})"}
          </button>
          <section :if={@show_corrections?} id="audit-log" class="mt-2 space-y-3">
            <ul class="divide-y divide-base-300 rounded-box border border-base-300 text-sm">
              <li :for={log <- @audit_logs} id={"audit-#{log.id}"} class="p-3 space-y-1">
                <div class="flex items-center justify-between gap-3">
                  <span class="font-medium">{log.field}</span>
                  <span class="text-xs text-base-content/50">{format_datetime(
                    log.inserted_at,
                    @current_scope.entity.timezone
                  )}</span>
                </div>
                <div class="text-xs text-base-content/50">by {user_label(log.user)}</div>
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
            id="edit-duty-form"
            phx-change="validate_edit"
            phx-submit="save_duty"
            class="mt-2"
          >
            <.char_count_input field={@edit_form[:title]} label="Title" max={60} required />
            <div class="fieldset mb-2">
              <label class="label mb-1" for="edit-duty-type">Type</label>
              <p id="edit-duty-type" class="font-medium text-info">{@duty.duty_type.name}</p>
            </div>
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
                name="duty[collaborator_ids][]"
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
              duty={@duty}
              current_scope={@current_scope}
              entity_slug={@current_scope.entity.slug}
              documents={cycle_documents(@duty)}
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
          <.form
            for={@correct_form}
            id="correct-form"
            phx-submit="confirm_correct"
            class="mt-4 space-y-3"
          >
            <.input field={@correct_form[:reason]} type="textarea" label="Reason (required)" required />
            <.input
              field={@correct_form[:replacement_due_by]}
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
              duty={@duty}
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

    duty =
      scope
      |> Duties.get_duty!(id)
      |> Map.update!(:events, fn events -> Enum.sort_by(events, & &1.inserted_at, DateTime) end)

    today = Urgency.today_for(scope.entity.timezone)

    tier = Urgency.tier(duty.duty_type, duty.due_by, today)
    live? = live_cycle?(duty)

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
     |> assign_correct_form(duty)
     |> assign(:step_files_modal_event_id, nil)
     |> assign(:step_files_modal_event, nil)
     |> assign(:voiding_document_id, nil)
     |> assign(:deleting_document_id, nil)
     |> assign(:show_corrections?, false)
     |> assign(:editing_note_id, nil)
     |> assign(:note_form, nil)
     |> assign(:recurring?, recurring?(duty))
     |> assign(:today, today)
     |> assign(:tier, tier)
     |> assign(:cycle_status, Index.cycle_status(duty))
     |> assign(:live?, live?)
     |> assign(:member_options, member_options(scope))
     |> assign_duty(duty)
     |> assign_done_form(duty)
     |> assign_progress_form()
     |> assign_skip_form(duty)
     |> assign_end_series_form()
     |> assign_edit_form(duty)}
  end

  @impl true
  def handle_event("close_modal_on_escape", _params, socket) do
    {:noreply, ModalEscape.close_duty_modals(socket)}
  end

  def handle_event("open_progress_modal", _params, socket) do
    {:noreply, socket |> assign(:show_progress_modal, true) |> assign_progress_form()}
  end

  def handle_event("close_progress_modal", _params, socket) do
    {:noreply, assign(socket, :show_progress_modal, false)}
  end

  def handle_event("confirm_start_progress", %{"progress" => %{"note" => note}}, socket) do
    scope = socket.assigns.current_scope
    duty = socket.assigns.duty

    case Duties.start_progress(scope, duty, %{note: note}) do
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

  def handle_event("toggle_corrections", _params, socket) do
    {:noreply, assign(socket, :show_corrections?, not socket.assigns.show_corrections?)}
  end

  def handle_event("open_edit_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_edit_modal, true)
     |> assign_edit_form(socket.assigns.duty)}
  end

  def handle_event("close_edit_modal", _params, socket) do
    {:noreply, assign(socket, :show_edit_modal, false)}
  end

  def handle_event("validate_edit", %{"duty" => params}, socket) do
    form =
      to_form(
        %{
          "title" => params["title"],
          "someday" => params["someday"],
          "due_by" => params["due_by"],
          "primary_assignee_id" => params["primary_assignee_id"]
        },
        as: "duty"
      )

    {:noreply, assign(socket, :edit_form, form)}
  end

  def handle_event("save_duty", %{"duty" => params}, socket) do
    scope = socket.assigns.current_scope
    duty = socket.assigns.duty

    attrs = %{
      title: params["title"],
      someday: params["someday"],
      due_by: parse_date(params["due_by"]),
      primary_assignee_id: normalize_assignee(params["primary_assignee_id"])
    }

    collaborator_ids = parse_collaborator_ids(params["collaborator_ids"])

    case Duties.update_duty(scope, duty, attrs) do
      {:ok, updated} ->
        case Duties.update_collaborators(scope, updated, collaborator_ids) do
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
         |> assign(:edit_form, to_form(changeset, as: "duty"))
         |> assign(:edit_collaborator_ids, collaborator_ids)}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  def handle_event("edit_note", %{"event_id" => event_id}, socket) do
    case find_event(socket.assigns.duty.events, event_id) do
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

    case find_event(socket.assigns.duty.events, event_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Event not found.")}

      event ->
        case Duties.edit_note(scope, event, %{note: note}) do
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
    duty = socket.assigns.duty

    attrs = %{
      note: params["note"],
      next_due_by: parse_date(params["next_due_by"])
    }

    case Duties.complete(scope, duty, attrs) do
      {:ok, _completed, _spawned} ->
        {:noreply,
         socket
         |> put_flash(:info, "Duty completed.")
         |> push_navigate(to: ~p"/entities/#{scope.entity.slug}/duties")}

      {:error, :next_due_required} ->
        {:noreply, put_flash(socket, :error, "Next due date is required for recurring duties.")}

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
        {:noreply, put_flash(socket, :error, "Could not complete duty.")}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  def handle_event("open_skip_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_skip_modal, true)
     |> assign_skip_form(socket.assigns.duty)}
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

    case Duties.skip(scope, socket.assigns.duty, attrs) do
      {:ok, _cancelled, _spawned} ->
        {:noreply,
         socket
         |> put_flash(:info, "Cycle skipped.")
         |> push_navigate(to: ~p"/entities/#{scope.entity.slug}/duties")}

      {:error, :next_due_required} ->
        {:noreply, put_flash(socket, :error, "Next due date is required for recurring duties.")}

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

    case Duties.end_series(scope, socket.assigns.duty, %{note: note}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Series ended.")
         |> push_navigate(to: ~p"/entities/#{scope.entity.slug}/duties")}

      {:error, :note_required} ->
        {:noreply, put_flash(socket, :error, "A reason is required.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not end series.")}
    end
  end

  def handle_event("open_correct_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_correct_modal, true)
     |> assign_correct_form(socket.assigns.duty)}
  end

  def handle_event("close_correct_modal", _params, socket) do
    {:noreply, assign(socket, :show_correct_modal, false)}
  end

  def handle_event("confirm_correct", %{"correct" => params}, socket) do
    scope = socket.assigns.current_scope
    duty = socket.assigns.duty

    attrs = %{
      reason: params["reason"],
      replacement_due_by: params["replacement_due_by"]
    }

    case Duties.mark_completed_in_error(scope, duty, attrs) do
      {:ok, _original, replacement} ->
        {:noreply,
         socket
         |> put_flash(:info, "Cycle marked in error. Replacement created.")
         |> push_navigate(to: ~p"/entities/#{scope.entity.slug}/duties/#{replacement.id}")}

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
    duty = Duties.get_duty!(scope, socket.assigns.duty.id)

    socket = assign_duty(socket, duty)

    case socket.assigns.step_files_modal_event_id do
      nil ->
        socket

      event_id ->
        assign(socket, :step_files_modal_event, find_event(duty.events, event_id))
    end
  end

  defp assign_duty(socket, duty) do
    doc_slots = parse_slots(duty.complete_documents)

    {slot_rows, _voided} =
      DocumentHelpers.completion_view(cycle_documents(duty), doc_slots)

    scope = socket.assigns.current_scope

    %{previous: series_previous, next: series_next} = Duties.series_neighbors(duty)

    socket
    |> assign(:duty, duty)
    |> assign(:series_previous, series_previous)
    |> assign(:series_next, series_next)
    |> assign(:doc_slots, doc_slots)
    |> assign(:required_docs, slot_rows)
    |> assign(:docs_complete?, Enum.all?(slot_rows, fn {_slot, live} -> live end))
    |> assign(:void_reason_required?, Duties.document_void_reason_required?(duty))
    |> assign(:audit_logs, Duties.list_audit_logs(duty))
    |> assign(:can_add_document?, can_add_document?(scope, duty))
    |> assign(
      :correctable?,
      Index.cycle_status(duty) == :completed and
        is_nil(duty.completed_in_error_at) and
        Authorization.can?(socket.assigns.current_scope, :mark_completed_in_error)
    )
  end

  defp member_options(scope) do
    Entities.list_entity_members(scope.entity)
    |> Enum.map(fn {user, _membership} -> {Tugas.Accounts.User.display_name(user), user.id} end)
  end

  defp assign_edit_form(socket, duty) do
    socket
    |> assign(:edit_collaborator_ids, Enum.map(duty.collaborators, & &1.user_id))
    |> assign(
      :edit_form,
      to_form(
        %{
          "title" => duty.title,
          "someday" => is_nil(duty.due_by),
          "due_by" => iso_date(duty.due_by),
          "primary_assignee_id" => duty.primary_assignee_id
        },
        as: "duty"
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

  defp can_add_document?(scope, duty) do
    Authorization.can?(scope, :edit_duty) or
      Authorization.can?(scope, :start_progress, duty)
  end

  defp event_accent("done"), do: "border-success"
  defp event_accent("skipped"), do: "border-warning"
  defp event_accent("series_ended"), do: "border-neutral"
  defp event_accent("in_progress"), do: "border-warning"
  defp event_accent(_), do: "border-base-300"

  defp humanize_status("in_progress"), do: "In progress"
  defp humanize_status(status), do: String.capitalize(status)

  defp assign_done_form(socket, duty) do
    suggestion =
      if socket.assigns.recurring? do
        Recurrence.next_due_suggestion(duty.duty_type, duty.due_by)
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

  defp assign_skip_form(socket, duty) do
    suggestion =
      Recurrence.next_due_suggestion(duty.duty_type, duty.due_by)

    assign(
      socket,
      :skip_form,
      to_form(%{"note" => "", "next_due_by" => iso_date(suggestion)}, as: :skip)
    )
  end

  defp assign_end_series_form(socket) do
    assign(socket, :end_series_form, to_form(%{"note" => ""}, as: :end_series))
  end

  defp assign_correct_form(socket, %Duty{} = duty) do
    assign(socket, :correct_form, correct_form(duty))
  end

  defp correct_form(%Duty{} = duty) do
    to_form(
      %{
        "reason" => "",
        "replacement_due_by" => duty.due_by && Date.to_iso8601(duty.due_by)
      },
      as: "correct"
    )
  end

  defp recurring?(duty) do
    Recurrence.recurring?(duty.duty_type) and is_nil(duty.series_ended_at)
  end

  defp live_cycle?(%Duty{completed_at: nil, closed_at: nil}), do: true
  defp live_cycle?(_), do: false

  defp doc_href(entity_slug, duty, doc) do
    ~p"/entities/#{entity_slug}/duties/#{duty.id}/documents/#{doc.id}"
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
