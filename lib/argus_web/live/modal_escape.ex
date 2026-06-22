defmodule ArgusWeb.ModalEscape do
  @moduledoc false

  @doc """
  Closes the topmost open obligation modal on `socket`, if any.
  Nested document-void UI is dismissed before the documents modal.
  """
  def close_obligation_modals(socket, opts \\ []) do
    end_series? = Keyword.get(opts, :end_series?, true)

    cond do
      socket.assigns[:voiding_document_id] ->
        Phoenix.Component.assign(socket, :voiding_document_id, nil)

      socket.assigns[:step_files_modal_event] ->
        socket
        |> Phoenix.Component.assign(:step_files_modal_event_id, nil)
        |> Phoenix.Component.assign(:step_files_modal_event, nil)
        |> Phoenix.LiveView.push_event("clear_step_files_persist", %{})
        |> Phoenix.Component.assign(:voiding_document_id, nil)

      socket.assigns[:show_completion_modal] ->
        socket
        |> Phoenix.Component.assign(:show_completion_modal, false)
        |> Phoenix.Component.assign(:active_completion_slot, nil)
        |> Phoenix.LiveView.push_event("clear_completion_modal_persist", %{})
        |> Phoenix.Component.assign(:voiding_document_id, nil)

      socket.assigns[:show_done_modal] ->
        Phoenix.Component.assign(socket, :show_done_modal, false)

      socket.assigns[:show_progress_modal] ->
        Phoenix.Component.assign(socket, :show_progress_modal, false)

      socket.assigns[:show_skip_modal] ->
        Phoenix.Component.assign(socket, :show_skip_modal, false)

      socket.assigns[:show_correct_modal] ->
        Phoenix.Component.assign(socket, :show_correct_modal, false)

      end_series? && socket.assigns[:show_end_series_modal] ->
        Phoenix.Component.assign(socket, :show_end_series_modal, false)

      socket.assigns[:show_edit_modal] ->
        Phoenix.Component.assign(socket, :show_edit_modal, false)

      socket.assigns[:editing_note_id] ->
        socket
        |> Phoenix.Component.assign(:editing_note_id, nil)
        |> Phoenix.Component.assign(:note_form, nil)

      true ->
        socket
    end
  end

  @doc """
  Closes the obligation type editor modal on `socket`, if open.
  """
  def close_type_modal(socket) do
    if socket.assigns[:type_form] do
      Phoenix.Component.assign(socket, type_form: nil, editing: nil)
    else
      socket
    end
  end
end
