defmodule Argus.ObligationsFixtures do
  @moduledoc """
  Test helpers for obligations.
  """

  alias Argus.Entities
  alias Argus.Obligations.Type
  alias Argus.Repo

  import Argus.AccountsFixtures

  def type_fixture(%Entities.Entity{} = entity, attrs \\ %{}) do
    defaults = %{
      name: "Type #{System.unique_integer([:positive])}",
      recurring_interval: "none",
      complete_note_required: false,
      complete_documents: "",
      reminder_offsets: ""
    }

    attrs = Enum.into(attrs, defaults)

    %Type{entity_id: entity.id}
    |> Type.changeset(attrs)
    |> Repo.insert!()
  end

  def member_fixture(%Entities.Entity{} = entity) do
    user = user_fixture()

    %Entities.Membership{
      user_id: user.id,
      entity_id: entity.id,
      role: "member",
      accepted_at: DateTime.utc_now(:second)
    }
    |> Entities.Membership.changeset(%{})
    |> Repo.insert!()

    user
  end

  def obligation_fixture(scope, attrs \\ %{}) do
    type = type_fixture(scope.entity, Map.get(attrs, :type_attrs, %{}))
    assignee = member_fixture(scope.entity)

    attrs =
      Map.merge(
        %{
          title: "Obligation #{System.unique_integer([:positive])}",
          obligation_type_id: type.id,
          primary_assignee_id: assignee.id,
          due_by: ~D[2026-06-15]
        },
        Map.drop(attrs, [:type_attrs])
      )

    {:ok, obligation} = Argus.Obligations.create_obligation(scope, attrs)
    {scope, obligation}
  end
end