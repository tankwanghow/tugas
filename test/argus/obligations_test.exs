defmodule Argus.ObligationsTest do
  use Argus.DataCase, async: true

  alias Argus.Obligations

  import Argus.EntitiesFixtures, only: [manager_scope_fixture: 0, member_scope_fixture: 0]
  import Argus.ObligationsFixtures

  describe "create_obligation/2" do
    test "creates obligation, open event, snapshots type rules, and optional open note" do
      scope = manager_scope_fixture()

      type =
        type_fixture(scope.entity, complete_note_required: true, complete_documents: "receipt")

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

  describe "start_progress/2" do
    test "creates in_progress event" do
      {scope, obligation} = assigned_member_scope_fixture()
      assert {:ok, event} = Obligations.start_progress(scope, obligation)
      assert event.status == "in_progress"
    end

    test "is idempotent — rejected if already in_progress" do
      {scope, obligation} = assigned_member_scope_fixture()
      assert {:ok, _} = Obligations.start_progress(scope, obligation)
      assert {:error, :not_open} = Obligations.start_progress(scope, obligation)
    end
  end

  describe "complete/3" do
    test "marks done, stamps completed_at, and spawns next when recurring" do
      {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")

      assert {:ok, done_obligation, new_obligation} =
               Obligations.complete(scope, obligation, %{next_due_by: ~D[2026-02-15]})

      assert done_obligation.completed_at
      done_event = Obligations.latest_event(done_obligation)
      assert done_event.status == "done"
      assert new_obligation.due_by == ~D[2026-02-15]
      assert new_obligation.series_id == obligation.series_id
    end

    test "requires next_due_by for a recurring, not-ended series" do
      {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")
      assert {:error, :next_due_required} = Obligations.complete(scope, obligation, %{})
    end

    test "is idempotent — a second Done on the same cycle is rejected" do
      {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")

      assert {:ok, done_obligation, _} =
               Obligations.complete(scope, obligation, %{next_due_by: ~D[2026-02-15]})

      assert {:error, :not_live} =
               Obligations.complete(scope, done_obligation, %{next_due_by: ~D[2026-03-15]})
    end
  end

  describe "cancel_obligation/3" do
    test "requires a cancel reason" do
      {scope, obligation} = manager_obligation_scope_fixture()
      assert {:error, :note_required} = Obligations.cancel_obligation(scope, obligation, %{})
    end

    test "sets status cancelled and logs event with reason" do
      {scope, obligation} = manager_obligation_scope_fixture()

      assert {:ok, cancelled} =
               Obligations.cancel_obligation(scope, obligation, %{note: "No longer applicable"})

      assert cancelled.status == "cancelled"
      event = Obligations.latest_event(cancelled)
      assert event.status == "cancelled"
      assert event.note == "No longer applicable"
    end
  end

  describe "end_series/3" do
    test "requires a reason" do
      {scope, obligation} = recurring_manager_scope_fixture(interval: "monthly")
      assert {:error, :note_required} = Obligations.end_series(scope, obligation, %{})
    end

    test "cancels the current cycle so it can never be completed/spawn" do
      {scope, obligation} = recurring_manager_scope_fixture(interval: "monthly")

      assert {:ok, ended} =
               Obligations.end_series(scope, obligation, %{note: "Client left"})

      assert ended.status == "cancelled"
      assert ended.series_ended_at
      assert Obligations.latest_event(ended).note == "Client left"
      assert {:error, :not_live} = Obligations.complete(scope, ended, %{})
    end
  end

  describe "Obligation.changeset/2" do
    alias Argus.Obligations.Obligation
    alias Argus.Repo

    test "translates one-live-cycle-per-series unique constraint" do
      {_scope, obligation} = recurring_primary_scope_fixture()

      duplicate =
        %Obligation{
          entity_id: obligation.entity_id,
          series_id: obligation.series_id,
          status: "active",
          complete_note_required: false,
          complete_documents: ""
        }
        |> Obligation.changeset(%{
          title: "Racing successor",
          obligation_type_id: obligation.obligation_type_id,
          primary_assignee_id: obligation.primary_assignee_id,
          due_by: ~D[2026-07-15]
        })

      assert {:error, changeset} = Repo.insert(duplicate)

      assert {:series_id, {_msg, opts}} =
               Enum.find(changeset.errors, fn {field, _} -> field == :series_id end)

      assert opts[:constraint] == :unique
      assert opts[:constraint_name] == "obligations_one_live_cycle_per_series"
    end
  end

  describe "list_obligations/2" do
    test "filters by status and query" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)

      {:ok, live_obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF Live",
          obligation_type_id: type_fixture(manager.entity).id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-06-30]
        })

      {:ok, completed} =
        Obligations.create_obligation(manager, %{
          title: "EPF Done",
          obligation_type_id: type_fixture(manager.entity).id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-05-30]
        })

      assert {:ok, completed, _} =
               Obligations.complete(member_scope, completed, %{next_due_by: nil})

      {:ok, cancelled} =
        Obligations.create_obligation(manager, %{
          title: "EPF Cancelled",
          obligation_type_id: type_fixture(manager.entity).id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-04-30]
        })

      assert {:ok, _} =
               Obligations.cancel_obligation(manager, cancelled, %{note: "Superseded"})

      live_ids = manager |> Obligations.list_obligations(status: :live) |> Enum.map(& &1.id)

      completed_ids =
        manager |> Obligations.list_obligations(status: :completed) |> Enum.map(& &1.id)

      cancelled_ids =
        manager |> Obligations.list_obligations(status: :cancelled) |> Enum.map(& &1.id)

      assert live_obligation.id in live_ids
      refute completed.id in live_ids
      assert completed.id in completed_ids
      assert cancelled.id in cancelled_ids

      assert [found] = Obligations.list_obligations(manager, status: :all, query: "done")
      assert found.id == completed.id

      {:ok, other_live} =
        Obligations.create_obligation(manager, %{
          title: "Other Live",
          obligation_type_id: type_fixture(manager.entity).id,
          primary_assignee_id: manager.user.id,
          due_by: ~D[2026-07-01]
        })

      my_live_ids =
        member_scope |> Obligations.list_obligations(status: :my_live) |> Enum.map(& &1.id)

      my_completed_ids =
        member_scope |> Obligations.list_obligations(status: :my_completed) |> Enum.map(& &1.id)

      assert live_obligation.id in my_live_ids
      refute other_live.id in my_live_ids
      assert completed.id in my_completed_ids
      refute completed.id in my_live_ids
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
