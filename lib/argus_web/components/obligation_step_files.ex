defmodule ArgusWeb.ObligationStepFiles do
  @moduledoc """
  Per-step supporting (non-required) files: this event's live "other" files and a
  voided-other area, plus an additional-file uploader when the step is uploadable.
  """
  use Phoenix.Component

  import ArgusWeb.CoreComponents

  alias Argus.Obligations
  alias ArgusWeb.UploadSlotControls

  attr :event, :map, required: true
  attr :obligation, :map, required: true
  attr :current_scope, :map, required: true
  attr :entity_slug, :string, required: true
  attr :required_slots, :list, required: true
  attr :uploadable?, :boolean, required: true
  attr :voiding_document_id, :any, default: nil
  attr :deleting_document_id, :any, default: nil
  attr :void_reason_required?, :boolean, default: false
  attr :show_dates?, :boolean, default: true
  attr :id_prefix, :string, default: ""

  def step_files(assigns) do
    {live_other, voided_other} =
      ArgusWeb.ObligationLive.DocumentHelpers.step_files(
        assigns.event.documents,
        assigns.required_slots
      )

    assigns =
      assigns
      |> assign(:live_other, live_other)
      |> assign(:voided_other, voided_other)

    ~H"""
    <section id={"#{@id_prefix}step-files-#{@event.id}"} class="space-y-3">
      <div class="argus-meta-label">Supporting files</div>

      <p :if={@live_other == []} class="text-sm text-base-content/50">
        No supporting files on this step.
      </p>
      <ul :if={@live_other != []} class="divide-y divide-base-300 rounded-box border border-base-300">
        <li
          :for={doc <- @live_other}
          id={"#{@id_prefix}doc-row-#{doc.id}"}
          class="px-2.5 py-2 text-sm"
        >
          <div class="flex items-center gap-2">
            <.doc_link
              href={"/entities/#{@entity_slug}/obligations/#{@obligation.id}/documents/#{doc.id}"}
              name={file_name(doc)}
              class="link link-hover truncate min-w-0 flex-1"
            />
            <span
              :if={@show_dates?}
              class="text-xs text-base-content/50 shrink-0 whitespace-nowrap"
            >{format_datetime(doc.inserted_at)}</span>
            <div class="flex items-center gap-1 shrink-0">
              <%= if @deleting_document_id == doc.id do %>
                <button
                  id={"#{@id_prefix}confirm-delete-doc-#{doc.id}"}
                  type="button"
                  phx-click="delete_document"
                  phx-value-document_id={doc.id}
                  phx-value-event_id={@event.id}
                  phx-disable-with="Deleting…"
                  class="text-xl cursor-pointer"
                >
                  ✅
                </button>
                <button
                  type="button"
                  phx-click="cancel_delete_document"
                  class="text-xl cursor-pointer"
                >
                  ❌
                </button>
              <% else %>
                <button
                  :if={
                    @voiding_document_id != doc.id &&
                      Obligations.document_deletable?(@current_scope, @obligation, doc)
                  }
                  id={"#{@id_prefix}delete-doc-#{doc.id}"}
                  type="button"
                  phx-click="request_delete_document"
                  phx-value-document_id={doc.id}
                  phx-value-event_id={@event.id}
                  class="btn btn-ghost btn-xs h-6 min-h-6 px-1.5 text-error"
                >
                  Delete
                </button>
                <button
                  :if={
                    cycle_live?(@obligation) && @voiding_document_id != doc.id &&
                      Obligations.document_voidable?(@current_scope, @obligation, doc)
                  }
                  id={"#{@id_prefix}void-doc-#{doc.id}"}
                  type="button"
                  phx-click="void_document"
                  phx-value-document_id={doc.id}
                  class="btn btn-ghost btn-xs h-6 min-h-6 px-1.5 text-error"
                >
                  Void
                </button>
              <% end %>
            </div>
          </div>
          <.void_form
            :if={@voiding_document_id == doc.id}
            doc={doc}
            event_id={@event.id}
            void_reason_required?={@void_reason_required?}
            id_prefix={@id_prefix}
          />
        </li>
      </ul>

      <div :if={@uploadable?} class="rounded-box border border-dashed border-base-300 p-2.5">
        <UploadSlotControls.upload_slot_controls
          slot="additional"
          id_prefix={@id_prefix}
          upload_url={"/entities/#{@entity_slug}/obligations/#{@obligation.id}/documents"}
          obligation_id={@obligation.id}
          event_id={to_string(@event.id)}
          idle_label="Additional file"
          choose_button_id={"#{@id_prefix}select-additional-#{@event.id}"}
          choose_button_class="btn btn-outline btn-xs h-7 min-h-7 ml-auto"
        />
        <p class="mt-1 text-xs text-base-content/50">{Argus.Uploads.Limits.summary()}</p>
      </div>

      <section
        :if={@voided_other != []}
        id={"#{@id_prefix}step-voided-#{@event.id}"}
        class="space-y-1"
      >
        <div class="argus-meta-label">Voided files</div>
        <ul class="divide-y divide-base-300 rounded-box border border-base-300">
          <li
            :for={doc <- @voided_other}
            id={"#{@id_prefix}voided-doc-#{doc.id}"}
            class="px-2.5 py-2 text-sm"
          >
            <div class="flex items-center gap-x-2">
              <.doc_link
                href={"/entities/#{@entity_slug}/obligations/#{@obligation.id}/documents/#{doc.id}"}
                name={file_name(doc)}
                icon_class="size-3.5 text-base-content/40 shrink-0"
                class="link link-hover truncate min-w-0 flex-1 line-through text-base-content/40"
              />
              <span class="badge badge-xs badge-error shrink-0">voided</span>
              <span
                :if={@show_dates?}
                class="text-xs text-base-content/50 shrink-0 whitespace-nowrap"
              >{format_datetime(doc.inserted_at)}</span>
            </div>
            <p :if={doc.void_reason} class="text-xs text-base-content/50 mt-1 pl-5">
              Void reason: {doc.void_reason}
            </p>
          </li>
        </ul>
      </section>
    </section>
    """
  end

  attr :doc, :map, required: true
  attr :event_id, :string, required: true
  attr :void_reason_required?, :boolean, required: true
  attr :id_prefix, :string, required: true

  defp void_form(assigns) do
    ~H"""
    <.form
      for={%{}}
      id={"#{@id_prefix}void-form-#{@doc.id}"}
      phx-submit="confirm_void_document"
      class="mt-2 pl-5 space-y-2"
    >
      <input type="hidden" name="document_id" value={@doc.id} />
      <input type="hidden" name="event_id" value={@event_id} />
      <.input
        :if={@void_reason_required?}
        name="reason"
        type="text"
        label="Reason for voiding"
        required
      />
      <div class="flex flex-wrap gap-2">
        <.button class="btn btn-error btn-xs" phx-disable-with="Voiding…">Confirm void</.button>
        <button type="button" class="btn btn-ghost btn-xs" phx-click="cancel_void_document">Cancel</button>
      </div>
    </.form>
    """
  end

  defp file_name(%{file: file}) when is_map(file) do
    Map.get(file, "original") || Map.get(file, :original) || "file"
  end

  defp cycle_live?(%{completed_at: nil, closed_at: nil}), do: true
  defp cycle_live?(_), do: false
end
