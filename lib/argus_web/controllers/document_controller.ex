defmodule ArgusWeb.DocumentController do
  use ArgusWeb, :controller

  alias Argus.Accounts.Scope
  alias Argus.Entities
  alias Argus.Obligations
  alias Argus.Obligations.{Event, EventDocument, Obligation}
  alias Argus.Repo
  alias Argus.Uploads
  alias Argus.Uploads.Limits
  alias ArgusWeb.ObligationLive.DocumentHelpers

  import Ecto.Query

  @doc """
  Plain multipart upload of a document. Used by the `UploadDirect` client hook
  instead of LiveView's socket upload: a normal HTTP request does not depend on
  the live socket, so backgrounding the page during a long camera capture no
  longer loses the file (the socket-upload path dropped it on the resulting
  LiveView remount). Size limits are enforced server-side here, authoritatively.
  """
  def create(conn, %{"entity_slug" => slug, "obligation_id" => obligation_id} = params) do
    scope = entity_scope!(conn, slug)
    obligation = Obligations.get_obligation!(scope, obligation_id)

    upload = params["file"]
    document_slot = blank_to_nil(params["document_slot"])
    event = resolve_event(obligation, params["event_id"])

    with %Plug.Upload{path: path, filename: filename} <- upload,
         %Event{} = event <- event,
         :ok <- Limits.validate_size(filename, file_size(path)) do
      case Obligations.add_document(scope, obligation, event, upload, document_slot) do
        {:ok, document} -> json(conn, %{ok: true, id: document.id})
        :not_authorise -> error_json(conn, 403, "Not authorized.")
        {:error, _} -> error_json(conn, 422, "Could not add document.")
      end
    else
      {:error, message} when is_binary(message) -> error_json(conn, 413, message)
      nil -> error_json(conn, 422, "No step available to attach documents to.")
      _ -> error_json(conn, 400, "Choose a file to upload.")
    end
  end

  def show(conn, %{"entity_slug" => slug, "obligation_id" => obligation_id, "id" => id} = params) do
    user = conn.assigns.current_scope.user
    entity = Entities.get_entity_by_slug_for_user!(slug, user)
    obligation = get_obligation!(obligation_id, entity.id)
    document = get_document!(id, obligation.id)

    # Inline by default so previews can embed the file; ?download=1 forces a "Save as".
    disposition = if params["download"] in ~w(1 true), do: :attachment, else: :inline

    if File.exists?(Uploads.path(document)) do
      send_download(conn, {:file, Uploads.path(document)},
        filename: original_filename(document),
        disposition: disposition
      )
    else
      conn |> put_status(:not_found) |> text("Not found")
    end
  end

  defp entity_scope!(conn, slug) do
    user = conn.assigns.current_scope.user
    entity = Entities.get_entity_by_slug_for_user!(slug, user)
    membership = Entities.get_membership!(user, entity)
    Scope.put_entity(conn.assigns.current_scope, entity, membership)
  end

  defp resolve_event(obligation, id) when id in [nil, ""] do
    DocumentHelpers.upload_event(obligation.events)
  end

  defp resolve_event(obligation, id) do
    Enum.find(obligation.events, &(to_string(&1.id) == to_string(id)))
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp error_json(conn, status, message) do
    conn |> put_status(status) |> json(%{ok: false, error: message})
  end

  defp get_obligation!(id, entity_id) do
    case Repo.get_by(Obligation, id: id, entity_id: entity_id) do
      %Obligation{} = obligation -> obligation
      nil -> raise Ecto.NoResultsError, queryable: Obligation
    end
  end

  defp get_document!(id, obligation_id) do
    EventDocument
    |> join(:inner, [d], e in Event, on: d.obligation_event_id == e.id)
    |> where([d, e], d.id == ^id and e.obligation_id == ^obligation_id)
    |> Repo.one!()
  end

  defp original_filename(%EventDocument{file: file}) when is_map(file) do
    Map.get(file, "original") || Map.get(file, :original) || "document"
  end
end
