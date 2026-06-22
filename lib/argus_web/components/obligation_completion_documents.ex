defmodule ArgusWeb.ObligationCompletionDocuments do
  @moduledoc """
  Cycle-level required completion documents: one row per required slot (live file
  inline, or an uploader if missing) plus a voided-required section. All file
  management for required slots lives here; slots are immutable after upload.
  """
  use Phoenix.Component

  import ArgusWeb.CoreComponents

  alias Argus.Obligations
  alias ArgusWeb.UploadSlotControls

  attr :obligation, :map, required: true
  attr :current_scope, :map, required: true
  attr :entity_slug, :string, required: true
  attr :documents, :list, required: true
  attr :required_slots, :list, required: true
  attr :uploadable?, :boolean, required: true
  attr :voiding_document_id, :any, default: nil
  attr :deleting_document_id, :any, default: nil
  attr :void_reason_required?, :boolean, default: false
  attr :show_dates?, :boolean, default: true
  attr :id_prefix, :string, default: ""

  def completion_documents(assigns) do
    {slot_rows, voided} =
      ArgusWeb.ObligationLive.DocumentHelpers.completion_view(
        assigns.documents,
        assigns.required_slots
      )

    assigns =
      assigns
      |> assign(:slot_rows, slot_rows)
      |> assign(:voided, voided)

    ~H"""
    <section id={"#{@id_prefix}completion-docs"} class="space-y-3">
      <div :if={@slot_rows == []} class="text-sm text-base-content/50">
        This obligation type has no required completion documents.
      </div>

      <ul class="divide-y divide-base-300 rounded-box border border-base-300">
        <li
          :for={{slot, live} <- @slot_rows}
          id={"#{@id_prefix}completion-slot-#{slot}"}
          class="px-2.5 py-2 text-sm"
        >
          <div class="flex items-center gap-x-2">
            <.icon
              name={if(live, do: "hero-check-circle-mini", else: "hero-x-circle-mini")}
              class={["size-4 shrink-0", if(live, do: "text-success", else: "text-warning")]}
            />
            <span class="font-medium shrink-0 whitespace-nowrap">{slot}</span>

            <.doc_link
              :if={live}
              href={"/entities/#{@entity_slug}/obligations/#{@obligation.id}/documents/#{live.id}"}
              name={file_name(live)}
              class="link link-hover truncate min-w-0 flex-1"
            />
            <span
              :if={live && @show_dates?}
              class="text-xs text-base-content/50 shrink-0 whitespace-nowrap"
            >
              {format_datetime(live.inserted_at, :short)}
            </span>

            <div :if={live} class="flex items-center gap-1 shrink-0">
              <%= if @deleting_document_id == live.id do %>
                <button
                  id={"#{@id_prefix}confirm-delete-doc-#{live.id}"}
                  type="button"
                  phx-click="delete_document"
                  phx-value-document_id={live.id}
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
                    @voiding_document_id != live.id &&
                      Obligations.document_deletable?(@current_scope, @obligation, live)
                  }
                  id={"#{@id_prefix}delete-doc-#{live.id}"}
                  type="button"
                  phx-click="request_delete_document"
                  phx-value-document_id={live.id}
                  class="btn btn-ghost btn-xs h-6 min-h-6 px-1.5 text-error"
                >
                  Delete
                </button>
                <button
                  :if={
                    cycle_live?(@obligation) && @voiding_document_id != live.id &&
                      Obligations.document_voidable?(@current_scope, @obligation, live)
                  }
                  id={"#{@id_prefix}void-doc-#{live.id}"}
                  type="button"
                  phx-click="void_document"
                  phx-value-document_id={live.id}
                  class="btn btn-ghost btn-xs h-6 min-h-6 px-1.5 text-error"
                >
                  Void
                </button>
              <% end %>
            </div>

            <UploadSlotControls.upload_slot_controls
              :if={is_nil(live) and @uploadable?}
              slot={slot}
              id_prefix={@id_prefix}
              upload_url={"/entities/#{@entity_slug}/obligations/#{@obligation.id}/documents"}
              obligation_id={@obligation.id}
              completion_slot?={true}
              choose_button_id={"#{@id_prefix}select-slot-#{slot}"}
            />
          </div>

          <.void_form
            :if={live && @voiding_document_id == live.id}
            doc={live}
            void_reason_required?={@void_reason_required?}
            id_prefix={@id_prefix}
          />
        </li>
      </ul>

      <p :if={@uploadable? and @slot_rows != []} class="text-xs text-base-content/50">
        {Argus.Uploads.Limits.summary()}
      </p>

      <section :if={@voided != []} id={"#{@id_prefix}completion-voided"} class="space-y-1">
        <div class="argus-meta-label">Voided required files</div>
        <ul class="divide-y divide-base-300 rounded-box border border-base-300">
          <li
            :for={doc <- @voided}
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
              <span :if={doc.document_slot} class="badge badge-xs badge-ghost shrink-0">{doc.document_slot}</span>
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
