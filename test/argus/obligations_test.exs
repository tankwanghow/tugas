defmodule Argus.ObligationsTest do
  use Argus.DataCase, async: true

  alias Argus.Obligations

  import Argus.EntitiesFixtures, only: [manager_scope_fixture: 0, member_scope_fixture: 0]
  import Argus.ObligationsFixtures

  describe "create_obligation/2" do
    test "creates obligation, open event, snapshots type rules, and optional open note" do
      scope = manager_scope_fixture()
      type = type_fixture(scope.entity, complete_note_required: true, complete_documents: "receipt")
      assignee = member_fixture(scope.entity)

      attrs = %{
        title: "EPF Jan",
        obligation_type_id: type.id,
        primary_assignee_id: assignee.id,
        due_by: ~D[2026-01-15],
        open_note: "Submit by 15th"
      }

      assert {:ok, obligation} = Obligations.create_obligation(scope, attrs)
      assert obligation.series_id
      assert obligation.status == "active"
      assert obligation.complete_note_required == true
      assert obligation.complete_documents == "receipt"

      events = Obligations.list_events(obligation)
      assert hd(events).status == "open"
      assert hd(events).note == "Submit by 15th"
    end

    test "returns :not_authorise for members" do
      scope = member_scope_fixture()
      type = type_fixture(scope.entity)
      assignee = member_fixture(scope.entity)

      attrs = %{
        title: "EPF Jan",
        obligation_type_id: type.id,
        primary_assignee_id: assignee.id,
        due_by: ~D[2026-01-15]
      }

      assert :not_authorise = Obligations.create_obligation(scope, attrs)
    end
  end

  describe "live/1" do
    test "includes active incomplete obligations only" do
      {_scope, obligation} = obligation_fixture(manager_scope_fixture())

      assert [^obligation] =
               Obligations.live()
               |> Argus.Repo.all()
               |> Enum.filter(&(&1.id == obligation.id))

      obligation
      |> Ecto.Changeset.change(completed_at: DateTime.utc_now(:second))
      |> Argus.Repo.update!()

      refute Enum.any?(Obligations.live() |> Argus.Repo.all(), &(&1.id == obligation.id))
    end
  end
end