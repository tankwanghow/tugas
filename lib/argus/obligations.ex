defmodule Argus.Obligations do
  @moduledoc """
  Obligations domain — cycles, events, and workflow.
  """

  import Ecto.Query, warn: false

  alias Argus.Accounts.Scope
  alias Argus.Authorization
  alias Argus.Obligations.{Collaborator, Event, Obligation, Type}
  alias Argus.Repo

  def live(query \\ Obligation) do
    from(o in query, where: o.status == "active" and is_nil(o.completed_at))
  end

  def list_events(%Obligation{} = obligation) do
    Event
    |> where([e], e.obligation_id == ^obligation.id)
    |> order_by([e], asc: e.inserted_at)
    |> Repo.all()
  end

  def create_obligation(%Scope{} = scope, attrs) do
    with true <- Authorization.can?(scope, :create_obligation),
         {:ok, type} <- fetch_type_for_entity(scope, attrs),
         {:ok, obligation} <- insert_obligation(scope, attrs, type) do
      {:ok, obligation}
    else
      false -> :not_authorise
      {:error, _} = error -> error
    end
  end

  defp fetch_type_for_entity(%Scope{entity: entity}, attrs) do
    type_id = Map.get(attrs, :obligation_type_id) || Map.get(attrs, "obligation_type_id")

    case Repo.get(Type, type_id) do
      %Type{entity_id: nil} = type -> {:ok, type}
      %Type{entity_id: entity_id} = type when entity_id == entity.id -> {:ok, type}
      %Type{} -> {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  defp insert_obligation(%Scope{user: user, entity: entity}, attrs, %Type{} = type) do
    series_id = Ecto.UUID.generate()
    open_note = Map.get(attrs, :open_note) || Map.get(attrs, "open_note")
    collaborator_ids = Map.get(attrs, :collaborator_ids, []) || Map.get(attrs, "collaborator_ids", [])

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:obligation, fn _ ->
      %Obligation{
        entity_id: entity.id,
        series_id: series_id,
        status: "active",
        complete_note_required: type.complete_note_required,
        complete_documents: type.complete_documents
      }
      |> Obligation.changeset(attrs)
    end)
    |> maybe_insert_collaborators(collaborator_ids)
    |> Ecto.Multi.insert(:open_event, fn %{obligation: obligation} ->
      %Event{
        obligation_id: obligation.id,
        status_by_id: user.id
      }
      |> Event.changeset(%{status: "open", note: open_note})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{obligation: obligation}} -> {:ok, obligation}
      {:error, :obligation, changeset, _} -> {:error, changeset}
      {:error, :open_event, changeset, _} -> {:error, changeset}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  defp maybe_insert_collaborators(multi, []), do: multi

  defp maybe_insert_collaborators(multi, collaborator_ids) do
    Ecto.Multi.insert_all(multi, :collaborators, Collaborator, fn %{obligation: obligation} ->
      now = DateTime.utc_now(:second)

      Enum.map(collaborator_ids, fn user_id ->
        %{
          id: Ecto.UUID.generate(),
          obligation_id: obligation.id,
          user_id: user_id,
          inserted_at: now
        }
      end)
    end)
  end
end