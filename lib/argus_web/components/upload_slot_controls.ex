defmodule ArgusWeb.UploadSlotControls do
  @moduledoc """
  The per-slot "Choose file" control. Uploading is handled entirely by the
  `UploadDirect` client hook (a plain HTTP multipart POST to
  `DocumentController.create/2`), not LiveView's socket upload — so a long
  mobile camera/file pick that backgrounds the page and drops the socket can no
  longer lose the file. This component only renders the button plus a
  client-driven error line (shown synchronously by the hook, persisted across a
  reconnect by `UploadUiPersist`).
  """
  use Phoenix.Component

  alias ArgusWeb.LiveUpload

  attr :slot, :string, required: true
  attr :id_prefix, :string, required: true
  attr :upload_url, :string, required: true
  attr :obligation_id, :string, required: true
  attr :event_id, :string, default: nil
  attr :idle_label, :string, default: nil
  attr :completion_slot?, :boolean, default: false
  attr :choose_button_id, :string, required: true
  attr :choose_button_class, :string, default: "btn btn-primary btn-xs h-7 min-h-7 ml-auto"

  def upload_slot_controls(assigns) do
    ~H"""
    <div
      data-upload-slot-controls={"#{@id_prefix}#{@slot}"}
      class="flex-1 min-w-0"
    >
      <div data-upload-slot-actions class="flex items-center gap-1 justify-between w-full min-w-0">
        <span :if={@idle_label} class="text-sm text-base-content/70">{@idle_label}</span>
        <button
          id={@choose_button_id}
          type="button"
          phx-hook="UploadDirect"
          data-upload-url={@upload_url}
          data-obligation-id={@obligation_id}
          data-id-prefix={@id_prefix}
          data-slot={@slot}
          data-document-slot={if(@completion_slot?, do: @slot, else: "")}
          data-event-id={@event_id || ""}
          {LiveUpload.client_size_attrs()}
          class={@choose_button_class}
        >
          Choose file
        </button>
      </div>
      <div
        data-client-upload-error-row
        class="hidden flex items-center gap-2 w-full min-w-0"
      >
        <p data-client-upload-error class="text-xs text-error flex-1 min-w-0"></p>
        <button
          data-client-upload-dismiss
          type="button"
          class="cursor-pointer text-xl shrink-0"
          aria-label="Dismiss"
        >
          ❌
        </button>
      </div>
    </div>
    """
  end
end
