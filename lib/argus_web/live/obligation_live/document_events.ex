defmodule ArgusWeb.ObligationLive.DocumentEvents do
  @moduledoc false

  alias Argus.Obligations
  alias ArgusWeb.ObligationLive.DocumentHelpers

  @events ~w(
    open_documents_from_done
    open_step_files
    restore_step_files
    close_step_files
    open_completion_modal
    restore_completion_modal
    close_completion_modal
    document_uploaded
    request_delete_document
    cancel_delete_document
    delete_document
    void_document
    cancel_void_document
    confirm_void_document
  )

  defmacro __using__(_opts) do
    for event <- @events do
      quote do
        def handle_event(unquote(event), params, socket) do
          ArgusWeb.ObligationLive.DocumentEvents.dispatch(
            unquote(event),
            params,
            socket,
            &reload/1
          )
        end
      end
    end
  end

  def dispatch("open_documents_from_done", _params, socket, _reload) do
    {:noreply,
     socket
     |> Phoenix.Component.assign(:show_done_modal, false)
     |> Phoenix.Component.assign(:show_completion_modal, true)
     |> Phoenix.LiveView.push_event("persist_completion_modal", %{})}
  end

  def dispatch("open_step_files", %{"event_id" => event_id}, socket, _reload) do
    case DocumentHelpers.find_event(socket.assigns.obligation.events, event_id) do
      nil ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Step not found.")}

      event ->
        {:noreply,
         socket
         |> Phoenix.Component.assign(:step_files_modal_event_id, event.id)
         |> Phoenix.Component.assign(:step_files_modal_event, event)
         |> Phoenix.LiveView.push_event("persist_step_files", %{event_id: event.id})}
    end
  end

  def dispatch("restore_step_files", %{"event_id" => event_id}, socket, _reload) do
    case DocumentHelpers.find_event(socket.assigns.obligation.events, event_id) do
      nil ->
        {:noreply, Phoenix.LiveView.push_event(socket, "clear_step_files_persist", %{})}

      event ->
        {:noreply,
         socket
         |> Phoenix.Component.assign(:step_files_modal_event_id, event.id)
         |> Phoenix.Component.assign(:step_files_modal_event, event)}
    end
  end

  def dispatch("close_step_files", _params, socket, _reload) do
    {:noreply, close_document_modal(socket, :step_files)}
  end

  def dispatch("open_completion_modal", _params, socket, _reload) do
    {:noreply,
     socket
     |> Phoenix.Component.assign(:show_completion_modal, true)
     |> Phoenix.LiveView.push_event("persist_completion_modal", %{})}
  end

  def dispatch("restore_completion_modal", _params, socket, _reload) do
    {:noreply, Phoenix.Component.assign(socket, :show_completion_modal, true)}
  end

  def dispatch("close_completion_modal", _params, socket, _reload) do
    {:noreply, close_document_modal(socket, :completion)}
  end

  def dispatch("document_uploaded", _params, socket, reload) do
    socket = reload.(socket)

    # Close whichever document modal the upload came from, so a successful
    # upload dismisses the form. close_document_modal/2 also clears the
    # sessionStorage persistence, so a reconnect won't re-open it.
    socket =
      cond do
        socket.assigns[:show_completion_modal] -> close_document_modal(socket, :completion)
        socket.assigns[:step_files_modal_event_id] -> close_document_modal(socket, :step_files)
        true -> socket
      end

    {:noreply, socket}
  end

  def dispatch("request_delete_document", %{"document_id" => document_id}, socket, _reload) do
    {:noreply,
     socket
     |> Phoenix.Component.assign(:deleting_document_id, document_id)
     |> Phoenix.Component.assign(:voiding_document_id, nil)}
  end

  def dispatch("cancel_delete_document", _params, socket, _reload) do
    {:noreply, Phoenix.Component.assign(socket, :deleting_document_id, nil)}
  end

  def dispatch("delete_document", %{"document_id" => document_id} = params, socket, reload) do
    scope = socket.assigns.current_scope
    obligation = socket.assigns.obligation
    event_id = params["event_id"]

    case DocumentHelpers.find_event_document(obligation.events, event_id, document_id) do
      nil ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Document not found.")}

      document ->
        case Obligations.delete_document(scope, obligation, document) do
          {:ok, _} ->
            {:noreply,
             socket
             |> reload.()
             |> Phoenix.Component.assign(:deleting_document_id, nil)}

          :not_authorise ->
            {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Not authorized.")}

          {:error, _} ->
            {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Could not delete document.")}
        end
    end
  end

  def dispatch("void_document", %{"document_id" => document_id}, socket, _reload) do
    {:noreply,
     socket
     |> Phoenix.Component.assign(:voiding_document_id, document_id)
     |> Phoenix.Component.assign(:deleting_document_id, nil)}
  end

  def dispatch("cancel_void_document", _params, socket, _reload) do
    {:noreply, Phoenix.Component.assign(socket, :voiding_document_id, nil)}
  end

  def dispatch("confirm_void_document", %{"document_id" => document_id} = params, socket, reload) do
    scope = socket.assigns.current_scope
    obligation = socket.assigns.obligation
    reason = Map.get(params, "reason")
    event_id = Map.get(params, "event_id")

    case DocumentHelpers.find_event_document(obligation.events, event_id, document_id) do
      nil ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Document not found.")}

      document ->
        case Obligations.void_document(scope, obligation, document, %{reason: reason}) do
          {:ok, _} ->
            {:noreply,
             socket
             |> reload.()
             |> Phoenix.Component.assign(:voiding_document_id, nil)}

          :not_authorise ->
            {:noreply,
             Phoenix.LiveView.put_flash(socket, :error, "Not authorized to void this document.")}

          {:error, :reason_required} ->
            {:noreply,
             Phoenix.LiveView.put_flash(
               socket,
               :error,
               "A reason is required to void this document."
             )}

          {:error, _} ->
            {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Could not void document.")}
        end
    end
  end

  defp close_document_modal(socket, :step_files) do
    socket
    |> Phoenix.Component.assign(:step_files_modal_event_id, nil)
    |> Phoenix.Component.assign(:step_files_modal_event, nil)
    |> Phoenix.LiveView.push_event("clear_step_files_persist", %{})
    |> clear_document_ui_state()
  end

  defp close_document_modal(socket, :completion) do
    socket
    |> Phoenix.Component.assign(:show_completion_modal, false)
    |> Phoenix.LiveView.push_event("clear_completion_modal_persist", %{})
    |> clear_document_ui_state()
  end

  defp clear_document_ui_state(socket) do
    socket
    |> Phoenix.Component.assign(:voiding_document_id, nil)
    |> Phoenix.Component.assign(:deleting_document_id, nil)
  end
end
