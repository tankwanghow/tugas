defmodule Tugas.DutiesTest do
  use Tugas.DataCase, async: true

  alias Tugas.Duties

  import Tugas.AccountsFixtures, only: [user_fixture: 0]

  alias Tugas.Accounts.Scope

  import Tugas.EntitiesFixtures,
    only: [entity_scope_fixture: 0, manager_scope_fixture: 0, member_scope_fixture: 0]

  import Tugas.DutiesFixtures

  describe "scope without entity" do
    test "read APIs return :not_authorise instead of raising" do
      user = user_fixture()
      scope = Scope.for_user(user)

      assert :not_authorise = Duties.list_types(scope)
      assert :not_authorise = Duties.list_duties(scope)
      assert :not_authorise = Duties.list_duties_page(scope)
      assert :not_authorise = Duties.list_unassigned(scope)
      assert :not_authorise = Duties.list_recently_completed(scope)
    end
  end

  describe "create_duty/2" do
    test "rejects assignee and collaborators outside the entity" do
      manager = manager_scope_fixture()
      outsider = user_fixture()

      type = type_fixture(manager.entity)

      assert {:error, :invalid_assignee} =
               Duties.create_duty(manager, %{
                 title: "EPF Jan",
                 duty_type_id: type.id,
                 primary_assignee_id: outsider.id,
                 due_by: ~D[2026-01-15],
                 open_note: "Open"
               })

      member = member_fixture(manager.entity)

      assert {:error, :invalid_assignee} =
               Duties.create_duty(manager, %{
                 title: "EPF Feb",
                 duty_type_id: type.id,
                 collaborator_ids: [outsider.id],
                 due_by: ~D[2026-02-15],
                 open_note: "Open"
               })

      assert {:ok, _} =
               Duties.create_duty(manager, %{
                 title: "EPF Mar",
                 duty_type_id: type.id,
                 primary_assignee_id: member.id,
                 collaborator_ids: [member.id],
                 due_by: ~D[2026-03-15],
                 open_note: "Open"
               })
    end

    test "creates duty, open event, snapshots type rules, and open note" do
      scope = manager_scope_fixture()

      type = type_fixture(scope.entity, complete_documents: "receipt")

      assignee = member_fixture(scope.entity)

      attrs = %{
        title: "EPF Jan",
        duty_type_id: type.id,
        primary_assignee_id: assignee.id,
        due_by: ~D[2026-01-15],
        open_note: "Submit by 15th"
      }

      assert {:ok, duty} = Duties.create_duty(scope, attrs)
      assert duty.series_id
      assert is_nil(duty.completed_at)
      assert is_nil(duty.closed_at)
      assert duty.complete_documents == "receipt"

      events = Duties.list_events(duty)
      assert hd(events).status == "open"
      assert hd(events).note == "Submit by 15th"
    end

    test "returns :not_authorise for members" do
      scope = member_scope_fixture()
      type = type_fixture(scope.entity)
      assignee = member_fixture(scope.entity)

      attrs = %{
        title: "EPF Jan",
        duty_type_id: type.id,
        primary_assignee_id: assignee.id,
        due_by: ~D[2026-01-15]
      }

      assert :not_authorise = Duties.create_duty(scope, attrs)
    end

    test "allows creating without a primary assignee" do
      scope = manager_scope_fixture()
      type = type_fixture(scope.entity)

      attrs = %{
        title: "Unassigned filing",
        duty_type_id: type.id,
        primary_assignee_id: nil,
        due_by: ~D[2026-06-20],
        open_note: "Needs an owner"
      }

      assert {:ok, duty} = Duties.create_duty(scope, attrs)
      assert is_nil(duty.primary_assignee_id)
    end

    test "rejects a title longer than 60 characters" do
      scope = manager_scope_fixture()
      type = type_fixture(scope.entity)

      attrs = %{
        title: String.duplicate("x", 61),
        duty_type_id: type.id,
        due_by: ~D[2026-01-15],
        open_note: "open"
      }

      assert {:error, changeset} = Duties.create_duty(scope, attrs)
      assert "should be at most 60 character(s)" in errors_on(changeset).title
    end

    test "requires an open note" do
      scope = manager_scope_fixture()
      type = type_fixture(scope.entity)
      assignee = member_fixture(scope.entity)

      attrs = %{
        title: "EPF Jan",
        duty_type_id: type.id,
        primary_assignee_id: assignee.id,
        due_by: ~D[2026-01-15]
      }

      assert {:error, :note_required} = Duties.create_duty(scope, attrs)
    end
  end

  describe "update_duty/3 — audit log" do
    test "does not write a 'someday' audit row when editing a dated duty" do
      scope = manager_scope_fixture()
      type = type_fixture(scope.entity)

      {:ok, duty} =
        Duties.create_duty(scope, %{
          title: "Original title",
          duty_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      assert {:ok, _updated} =
               Duties.update_duty(scope, duty, %{title: "Updated title"})

      fields = Duties.list_audit_logs(duty) |> Enum.map(& &1.field)
      refute "someday" in fields
      assert "title" in fields
    end
  end

  describe "completed-in-error schema" do
    test "new correction fields default to nil on a created duty" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, duty} =
        Duties.create_duty(manager, %{
          title: "EPF",
          duty_type_id: type.id,
          due_by: ~D[2026-06-30],
          open_note: "open"
        })

      assert duty.completed_in_error_at == nil
      assert duty.completed_in_error_by_id == nil
      assert duty.completed_in_error_reason == nil
      assert duty.replaces_id == nil
      assert duty.replaced_by_id == nil
    end
  end

  describe "start_progress/3" do
    test "creates in_progress event with note" do
      {scope, duty} = assigned_member_scope_fixture()

      assert {:ok, event} =
               Duties.start_progress(scope, duty, %{note: "Gathering documents"})

      assert event.status == "in_progress"
      assert event.note == "Gathering documents"
    end

    test "requires a progress note" do
      {scope, duty} = assigned_member_scope_fixture()
      assert {:error, :note_required} = Duties.start_progress(scope, duty, %{})
    end

    test "allows multiple in_progress updates on a live cycle" do
      {scope, duty} = assigned_member_scope_fixture()
      assert {:ok, first} = Duties.start_progress(scope, duty, %{note: "Started"})
      assert {:ok, second} = Duties.start_progress(scope, duty, %{note: "Halfway"})

      assert first.status == "in_progress"
      assert second.status == "in_progress"
      assert first.id != second.id

      in_progress =
        Duties.list_events(duty)
        |> Enum.filter(&(&1.status == "in_progress"))

      assert length(in_progress) == 2
    end

    test "rejects a progress update once the cycle is done" do
      {scope, duty} = recurring_primary_scope_fixture(interval: "monthly")

      {:ok, done, _spawned} =
        Duties.complete(scope, duty, %{note: "Done", next_due_by: ~D[2026-02-15]})

      assert {:error, :not_live} = Duties.start_progress(scope, done, %{note: "Too late"})
    end
  end

  describe "complete/3" do
    test "marks done, stamps completed_at, and spawns next when recurring" do
      {scope, duty} = recurring_primary_scope_fixture(interval: "monthly")

      assert {:ok, done_duty, new_duty} =
               Duties.complete(scope, duty, %{
                 note: "Filed on time",
                 next_due_by: ~D[2026-02-15]
               })

      assert done_duty.completed_at
      done_event = Duties.latest_event(done_duty)
      assert done_event.status == "done"
      assert new_duty.due_by == ~D[2026-02-15]
      assert new_duty.series_id == duty.series_id
    end

    test "spawned next cycle inherits the completed cycle's opening note" do
      {scope, duty} = recurring_primary_scope_fixture(interval: "monthly")

      assert {:ok, _done, spawned} =
               Duties.complete(scope, duty, %{
                 note: "Filed on time",
                 next_due_by: ~D[2026-02-15]
               })

      open_event = Duties.latest_event(spawned)
      assert open_event.status == "open"
      assert open_event.note == "Recurring task opened"
    end

    test "requires next_due_by for a recurring, not-ended series" do
      {scope, duty} = recurring_primary_scope_fixture(interval: "monthly")

      assert {:error, :next_due_required} =
               Duties.complete(scope, duty, %{note: "Done"})
    end

    test "rejects complete on another entity's duty" do
      manager = manager_scope_fixture()
      other_scope = entity_scope_fixture()
      {_other_scope, duty} = duty_fixture(other_scope)

      assert :not_found =
               Duties.complete(manager, duty, %{
                 note: "Done",
                 next_due_by: ~D[2026-07-01]
               })
    end

    test "requires a completion note" do
      {scope, duty} = assigned_member_scope_fixture()
      assert {:error, :note_required} = Duties.complete(scope, duty, %{})
    end

    test "is idempotent — a second Done on the same cycle is rejected" do
      {scope, duty} = recurring_primary_scope_fixture(interval: "monthly")

      assert {:ok, done_duty, _} =
               Duties.complete(scope, duty, %{
                 note: "Done",
                 next_due_by: ~D[2026-02-15]
               })

      assert {:error, :not_live} =
               Duties.complete(scope, done_duty, %{
                 note: "Again",
                 next_due_by: ~D[2026-03-15]
               })
    end
  end

  describe "skip/3" do
    test "one-off skip closes the cycle with a skipped event, no successor" do
      {scope, duty} = manager_duty_scope_fixture()

      assert {:ok, closed, nil} = Duties.skip(scope, duty, %{note: "drop it"})
      assert closed.closed_at
      assert is_nil(closed.completed_at)

      events = Duties.list_events(closed)
      assert Enum.any?(events, &(&1.status == "skipped" and &1.note == "drop it"))

      assert Duties.list_duties(scope, status: :live)
             |> Enum.all?(&(&1.id != closed.id))
    end

    test "recurring skip requires next_due_by and spawns the next cycle" do
      {scope, duty} = recurring_manager_scope_fixture(interval: "monthly")

      assert {:error, :next_due_required} = Duties.skip(scope, duty, %{note: "skip"})

      assert {:ok, closed, %Tugas.Duties.Duty{} = spawned} =
               Duties.skip(scope, duty, %{note: "skip", next_due_by: ~D[2026-08-01]})

      assert closed.closed_at
      assert spawned.series_id == closed.series_id
      assert is_nil(spawned.closed_at) and is_nil(spawned.completed_at)
    end

    test "skip requires a note" do
      {scope, duty} = manager_duty_scope_fixture()
      assert {:error, _} = Duties.skip(scope, duty, %{note: ""})
    end

    test "is idempotent — a second skip on the same cycle is rejected" do
      {scope, duty} = recurring_manager_scope_fixture(interval: "monthly")

      assert {:ok, closed, _} =
               Duties.skip(scope, duty, %{
                 note: "Skip",
                 next_due_by: ~D[2026-02-15]
               })

      assert {:error, :not_live} =
               Duties.skip(scope, closed, %{
                 note: "Again",
                 next_due_by: ~D[2026-03-15]
               })
    end
  end

  describe "complete/skip on a dateless cycle" do
    test "completing a dateless recurring duty needs no next_due and spawns nothing" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity, recurring_interval: "monthly")

      {:ok, ob} =
        Duties.create_duty(manager, %{
          title: "Someday recurring",
          duty_type_id: type.id,
          someday: true,
          open_note: "n"
        })

      assert ob.due_by == nil
      assert {:ok, _completed, nil} = Duties.complete(manager, ob, %{note: "done"})
    end
  end

  describe "end_series/3" do
    test "requires a reason" do
      {scope, duty} = recurring_manager_scope_fixture(interval: "monthly")
      assert {:error, :note_required} = Duties.end_series(scope, duty, %{})
    end

    test "stamps closed_at + series_ended_at with a series_ended event" do
      {scope, duty} = recurring_manager_scope_fixture(interval: "monthly")

      assert {:ok, ended} =
               Duties.end_series(scope, duty, %{note: "Client left"})

      assert ended.closed_at
      assert ended.series_ended_at

      events = Duties.list_events(ended)
      assert Enum.any?(events, &(&1.status == "series_ended"))
      assert Duties.latest_event(ended).note == "Client left"
      assert {:error, :not_live} = Duties.complete(scope, ended, %{note: "Too late"})
    end
  end

  describe "Duty.changeset/2" do
    alias Tugas.Duties.Duty
    alias Tugas.Repo

    test "requires due_by normally" do
      cs =
        Duty.changeset(%Duty{}, %{
          title: "t",
          duty_type_id: Ecto.UUID.generate()
        })

      refute cs.valid?
      assert %{due_by: ["can't be blank"]} = errors_on(cs)
    end

    test "someday=true makes due_by optional and force-nils it" do
      cs =
        Duty.changeset(%Duty{}, %{
          title: "t",
          duty_type_id: Ecto.UUID.generate(),
          due_by: ~D[2026-01-01],
          someday: true
        })

      refute Keyword.has_key?(cs.errors, :due_by)
      assert Ecto.Changeset.get_field(cs, :due_by) == nil
    end

    test "translates one-live-cycle-per-series unique constraint" do
      {_scope, duty} = recurring_primary_scope_fixture()

      duplicate =
        %Duty{
          entity_id: duty.entity_id,
          series_id: duty.series_id,
          complete_documents: ""
        }
        |> Duty.changeset(%{
          title: "Racing successor",
          duty_type_id: duty.duty_type_id,
          primary_assignee_id: duty.primary_assignee_id,
          due_by: ~D[2026-07-15]
        })

      assert {:error, changeset} = Repo.insert(duplicate)

      assert {:series_id, {_msg, opts}} =
               Enum.find(changeset.errors, fn {field, _} -> field == :series_id end)

      assert opts[:constraint] == :unique
      assert opts[:constraint_name] == "duties_one_live_cycle_per_series"
    end
  end

  describe "list_duties/2" do
    test "filters by status and query" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)

      {:ok, live_duty} =
        Duties.create_duty(manager, %{
          title: "EPF Live",
          duty_type_id: type_fixture(manager.entity).id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-06-30],
          open_note: "Live"
        })

      {:ok, completed} =
        Duties.create_duty(manager, %{
          title: "EPF Done",
          duty_type_id: type_fixture(manager.entity).id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-05-30],
          open_note: "Done cycle"
        })

      assert {:ok, completed, _} =
               Duties.complete(member_scope, completed, %{
                 note: "Completed",
                 next_due_by: nil
               })

      {:ok, skipped} =
        Duties.create_duty(manager, %{
          title: "EPF Skipped",
          duty_type_id: type_fixture(manager.entity).id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-04-30],
          open_note: "Skip cycle"
        })

      assert {:ok, _, nil} =
               Duties.skip(manager, skipped, %{note: "Superseded"})

      live_ids = manager |> Duties.list_duties(status: :live) |> Enum.map(& &1.id)

      completed_ids =
        manager |> Duties.list_duties(status: :completed) |> Enum.map(& &1.id)

      skipped_ids =
        manager |> Duties.list_duties(status: :skipped) |> Enum.map(& &1.id)

      assert live_duty.id in live_ids
      refute completed.id in live_ids
      assert completed.id in completed_ids
      assert skipped.id in skipped_ids

      assert [found] = Duties.list_duties(manager, status: :all, query: "done")
      assert found.id == completed.id

      {:ok, other_live} =
        Duties.create_duty(manager, %{
          title: "Other Live",
          duty_type_id: type_fixture(manager.entity).id,
          primary_assignee_id: manager.user.id,
          due_by: ~D[2026-07-01],
          open_note: "Other"
        })

      my_live_ids =
        member_scope |> Duties.list_duties(status: :my_live) |> Enum.map(& &1.id)

      my_completed_ids =
        member_scope |> Duties.list_duties(status: :my_completed) |> Enum.map(& &1.id)

      assert live_duty.id in my_live_ids
      refute other_live.id in my_live_ids
      assert completed.id in my_completed_ids
      refute completed.id in my_live_ids
    end

    test "my_skipped and my_all scope to the user across lifecycles" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)
      type = type_fixture(manager.entity)

      {:ok, mine_live} =
        Duties.create_duty(manager, %{
          title: "Mine Live",
          duty_type_id: type.id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-06-30],
          open_note: "live"
        })

      {:ok, mine_to_skip} =
        Duties.create_duty(manager, %{
          title: "Mine Skip",
          duty_type_id: type.id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-05-30],
          open_note: "skip"
        })

      assert {:ok, mine_skipped, nil} =
               Duties.skip(manager, mine_to_skip, %{note: "superseded"})

      {:ok, others} =
        Duties.create_duty(manager, %{
          title: "Theirs Skip",
          duty_type_id: type.id,
          primary_assignee_id: manager.user.id,
          due_by: ~D[2026-05-15],
          open_note: "skip"
        })

      assert {:ok, others_skipped, nil} = Duties.skip(manager, others, %{note: "nope"})

      my_skipped =
        member_scope |> Duties.list_duties(status: :my_skipped) |> Enum.map(& &1.id)

      assert mine_skipped.id in my_skipped
      refute others_skipped.id in my_skipped

      my_all = member_scope |> Duties.list_duties(status: :my_all) |> Enum.map(& &1.id)
      assert mine_live.id in my_all
      assert mine_skipped.id in my_all
      refute others_skipped.id in my_all
    end
  end

  describe "list_duties/2 date filters" do
    setup do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = Tugas.DutiesFixtures.type_fixture(manager.entity)

      {:ok, early} =
        Tugas.Duties.create_duty(manager, %{
          title: "Early",
          duty_type_id: type.id,
          due_by: ~D[2026-06-05],
          open_note: "early"
        })

      {:ok, mid} =
        Tugas.Duties.create_duty(manager, %{
          title: "Mid",
          duty_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "mid"
        })

      {:ok, late} =
        Tugas.Duties.create_duty(manager, %{
          title: "Late",
          duty_type_id: type.id,
          due_by: ~D[2026-06-25],
          open_note: "late"
        })

      {:ok, someday} =
        Tugas.Duties.create_duty(manager, %{
          title: "Someday duty",
          duty_type_id: type.id,
          someday: true,
          open_note: "someday"
        })

      %{manager: manager, early: early, mid: mid, late: late, someday: someday}
    end

    test "due_after and due_before restrict to a month window", %{
      manager: manager,
      early: early,
      mid: mid,
      late: late
    } do
      duties =
        Tugas.Duties.list_duties(manager,
          status: :live,
          due_after: ~D[2026-06-01],
          due_before: ~D[2026-06-20]
        )

      ids = Enum.map(duties, & &1.id)
      assert early.id in ids
      assert mid.id in ids
      refute late.id in ids
    end

    test "dateless: true returns only nil due_by duties", %{
      manager: manager,
      someday: someday,
      mid: mid
    } do
      duties = Tugas.Duties.list_duties(manager, status: :live, dateless: true)
      ids = Enum.map(duties, & &1.id)
      assert someday.id in ids
      refute mid.id in ids
    end
  end

  describe "list_unassigned/1 and list_recently_completed/1" do
    test "list_unassigned returns live duties with no primary assignee" do
      manager = manager_scope_fixture()
      type = type_fixture(manager.entity)
      assignee = member_fixture(manager.entity)

      {:ok, unassigned} =
        Duties.create_duty(manager, %{
          title: "Needs owner",
          duty_type_id: type.id,
          primary_assignee_id: nil,
          due_by: ~D[2026-06-20],
          open_note: "Unassigned"
        })

      {:ok, _assigned} =
        Duties.create_duty(manager, %{
          title: "Has owner",
          duty_type_id: type.id,
          primary_assignee_id: assignee.id,
          due_by: ~D[2026-06-21],
          open_note: "Assigned"
        })

      ids = manager |> Duties.list_unassigned() |> Enum.map(& &1.id)
      assert unassigned.id in ids
      assert length(ids) == 1
    end

    test "list_recently_completed returns duties completed within 14 days" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)
      type = type_fixture(manager.entity)

      {:ok, recent} =
        Duties.create_duty(manager, %{
          title: "Just done",
          duty_type_id: type.id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-06-01],
          open_note: "Recent"
        })

      assert {:ok, _, _} =
               Duties.complete(member_scope, recent, %{note: "Done", next_due_by: nil})

      ids = manager |> Duties.list_recently_completed() |> Enum.map(& &1.id)
      assert recent.id in ids
    end

    test "my_live excludes unassigned duties for members" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)
      type = type_fixture(manager.entity)

      {:ok, unassigned} =
        Duties.create_duty(manager, %{
          title: "Nobody assigned",
          duty_type_id: type.id,
          primary_assignee_id: nil,
          due_by: ~D[2026-06-20],
          open_note: "Nobody"
        })

      my_live_ids =
        member_scope |> Duties.list_duties(status: :my_live) |> Enum.map(& &1.id)

      refute unassigned.id in my_live_ids
    end
  end

  describe "event_summaries_for/1" do
    test "returns event count and latest event with status_by" do
      {scope, duty} = assigned_member_scope_fixture()

      assert {:ok, _} =
               Duties.start_progress(scope, duty, %{note: "Working on it"})

      summaries = Duties.event_summaries_for([duty])
      summary = Map.fetch!(summaries, duty.id)

      assert summary.event_count == 2
      assert summary.latest_event.status == "in_progress"
      assert summary.latest_event.status_by.email == scope.user.email
    end
  end

  describe "live/1" do
    test "includes active incomplete duties only" do
      {_scope, duty} = duty_fixture(manager_scope_fixture())

      assert [_] =
               Duties.live()
               |> Tugas.Repo.all()
               |> Enum.filter(&(&1.id == duty.id))

      duty
      |> Ecto.Changeset.change(completed_at: DateTime.utc_now(:second))
      |> Tugas.Repo.update!()

      refute Enum.any?(Duties.live() |> Tugas.Repo.all(), &(&1.id == duty.id))
    end
  end

  describe "list_duties_page/2" do
    setup do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      mk = fn title, due ->
        {:ok, o} =
          Duties.create_duty(manager, %{
            title: title,
            duty_type_id: type.id,
            due_by: due,
            open_note: "n"
          })

        o
      end

      a = mk.("Alpha", ~D[2026-03-01])
      b = mk.("bravo", ~D[2026-01-01])
      c = mk.("Charlie", ~D[2026-02-01])
      %{manager: manager, a: a, b: b, c: c}
    end

    test "sorts due_asc with stable keyset paging", %{manager: m, a: a, b: b, c: c} do
      page1 = Duties.list_duties_page(m, status: :live, sort: :due_asc, limit: 2)
      assert Enum.map(page1.rows, & &1.id) == [b.id, c.id]
      refute page1.end?

      page2 =
        Duties.list_duties_page(m,
          status: :live,
          sort: :due_asc,
          limit: 2,
          cursor: page1.cursor
        )

      assert Enum.map(page2.rows, & &1.id) == [a.id]
      assert page2.end?
    end

    test "sorts due_desc and title", %{manager: m, a: a, b: b, c: c} do
      desc = Duties.list_duties_page(m, status: :live, sort: :due_desc, limit: 10)
      assert Enum.map(desc.rows, & &1.id) == [a.id, c.id, b.id]

      title = Duties.list_duties_page(m, status: :live, sort: :title, limit: 10)
      assert Enum.map(title.rows, & &1.id) == [a.id, b.id, c.id]
    end

    test "search filters by title in SQL", %{manager: m, b: b} do
      page = Duties.list_duties_page(m, status: :live, query: "brav")
      assert Enum.map(page.rows, & &1.id) == [b.id]
    end

    test "due_before and due_after bound the window", %{manager: m, b: b, c: c, a: a} do
      before =
        Duties.list_duties_page(m,
          status: :live,
          sort: :due_asc,
          due_before: ~D[2026-02-15],
          limit: 10
        )

      assert Enum.map(before.rows, & &1.id) == [b.id, c.id]

      after_ =
        Duties.list_duties_page(m,
          status: :live,
          sort: :due_asc,
          due_after: ~D[2026-02-15],
          limit: 10
        )

      assert Enum.map(after_.rows, & &1.id) == [a.id]
    end

    test "limit: :all returns everything with end? true", %{manager: m} do
      page = Duties.list_duties_page(m, status: :live, sort: :due_asc, limit: :all)
      assert length(page.rows) == 3
      assert page.end?
      assert page.cursor == nil
    end

    test "my_* status scopes to the user's work and still applies the SQL search", %{manager: m} do
      member = member_scope_on_entity(m.entity)
      type = type_fixture(m.entity)

      mk = fn title, assignee_id ->
        {:ok, o} =
          Duties.create_duty(m, %{
            title: title,
            duty_type_id: type.id,
            primary_assignee_id: assignee_id,
            due_by: ~D[2026-04-01],
            open_note: "n"
          })

        o
      end

      mine = mk.("Quarterly VAT return", member.user.id)
      _other_mine = mk.("Annual audit", member.user.id)
      _unassigned = mk.("VAT something unassigned", nil)

      # my_live excludes the unassigned "VAT" row (not the member's work) and the
      # search drops "Annual audit", leaving only the member's VAT duty.
      page = Duties.list_duties_page(member, status: :my_live, query: "vat")
      assert Enum.map(page.rows, & &1.id) == [mine.id]
    end
  end

  describe "list_duties_page/2 — someday sort" do
    setup do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      dated =
        for {t, d} <- [{"Dated A", ~D[2026-02-01]}, {"Dated B", ~D[2026-03-01]}] do
          {:ok, o} =
            Duties.create_duty(manager, %{
              title: t,
              duty_type_id: type.id,
              due_by: d,
              open_note: "n"
            })

          o
        end

      someday =
        for t <- ["Someday X", "Someday Y", "Someday Z"] do
          {:ok, o} =
            Duties.create_duty(manager, %{
              title: t,
              duty_type_id: type.id,
              someday: true,
              open_note: "n"
            })

          o
        end

      %{manager: manager, dated: dated, someday: someday}
    end

    test "live lifecycle now includes both dated and dateless duties", %{
      manager: m,
      dated: dated,
      someday: someday
    } do
      page = Duties.list_duties_page(m, status: :live, limit: :all)
      ids = Enum.map(page.rows, & &1.id) |> Enum.sort()
      assert ids == Enum.map(dated ++ someday, & &1.id) |> Enum.sort()
    end

    test "someday sort floats no-due-date duties to the top, then dated by due date", %{
      manager: m,
      dated: [a, b],
      someday: someday
    } do
      page = Duties.list_duties_page(m, status: :live, sort: :someday, limit: :all)
      {top, bottom} = page.rows |> Enum.map(& &1.id) |> Enum.split(3)

      assert Enum.sort(top) == Enum.map(someday, & &1.id) |> Enum.sort()
      assert bottom == [a.id, b.id]
    end

    test "someday sort keyset-pages dateless-first with no dup or skip", %{
      manager: m,
      dated: [a, b],
      someday: someday
    } do
      p1 = Duties.list_duties_page(m, status: :live, sort: :someday, limit: 2)

      p2 =
        Duties.list_duties_page(m,
          status: :live,
          sort: :someday,
          limit: 2,
          cursor: p1.cursor
        )

      p3 =
        Duties.list_duties_page(m,
          status: :live,
          sort: :someday,
          limit: 2,
          cursor: p2.cursor
        )

      assert p3.end?

      ids = Enum.map(p1.rows ++ p2.rows ++ p3.rows, & &1.id)
      assert length(ids) == 5
      assert length(Enum.uniq(ids)) == 5

      {top, bottom} = Enum.split(ids, 3)
      assert Enum.sort(top) == Enum.map(someday, & &1.id) |> Enum.sort()
      assert bottom == [a.id, b.id]
    end

    test "completed lifecycle includes a completed dateless duty", %{
      manager: m,
      someday: [sx | _]
    } do
      {:ok, _, _} = Duties.complete(m, sx, %{note: "d"})
      page = Duties.list_duties_page(m, status: :completed, sort: :someday, limit: :all)
      assert sx.id in Enum.map(page.rows, & &1.id)
    end
  end

  describe "mark_completed_in_error/3" do
    test "flags the done cycle and spawns a standalone one-off replacement" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      member = member_scope_on_entity(manager.entity)
      type = type_fixture(manager.entity)

      {:ok, duty} =
        Duties.create_duty(manager, %{
          title: "EPF Jan",
          duty_type_id: type.id,
          primary_assignee_id: member.user.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _spawned} = Duties.complete(manager, duty, %{note: "Done"})

      assert {:ok, original, replacement} =
               Duties.mark_completed_in_error(manager, done, %{reason: "Wrong figures filed"})

      # original flagged, not mutated into a live cycle
      assert original.completed_in_error_at
      assert original.completed_in_error_by_id == manager.user.id
      assert original.completed_in_error_reason == "Wrong figures filed"
      assert original.replaced_by_id == replacement.id
      assert original.completed_at == done.completed_at

      # replacement is a fresh, live, standalone one-off
      assert replacement.series_id != original.series_id
      assert replacement.series_ended_at
      assert replacement.closed_at == nil
      assert replacement.completed_at == nil
      assert replacement.due_by == ~D[2026-06-15]
      assert replacement.title == "EPF Jan"
      assert replacement.primary_assignee_id == member.user.id
      assert replacement.replaces_id == original.id

      # open event carries the reason
      open_event = Duties.latest_event(replacement)
      assert open_event.status == "open"
      assert open_event.note == "Wrong figures filed"

      # an audit row was written on the original
      assert Enum.any?(
               Duties.list_audit_logs(original),
               &(&1.field == "completed_in_error" and &1.new_value == "Wrong figures filed")
             )
    end

    test "replacement_due_by overrides the inherited due date" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, duty} =
        Duties.create_duty(manager, %{
          title: "EPF",
          duty_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _} = Duties.complete(manager, duty, %{note: "Done"})

      assert {:ok, _original, replacement} =
               Duties.mark_completed_in_error(manager, done, %{
                 reason: "redo",
                 replacement_due_by: ~D[2026-07-01]
               })

      assert replacement.due_by == ~D[2026-07-01]
    end

    test "a blank replacement_due_by falls back to the original's due date" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, duty} =
        Duties.create_duty(manager, %{
          title: "EPF",
          duty_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _} = Duties.complete(manager, duty, %{note: "Done"})

      # A cleared date field submits "" — must not crash; falls back to original due_by.
      assert {:ok, _original, replacement} =
               Duties.mark_completed_in_error(manager, done, %{
                 reason: "redo",
                 replacement_due_by: ""
               })

      assert replacement.due_by == ~D[2026-06-15]
    end

    test "completing the one-off replacement does not require next_due and does not spawn" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      # recurring type — but the replacement must still behave as a one-off
      type = type_fixture(manager.entity, recurring_interval: "monthly")

      {:ok, duty} =
        Duties.create_duty(manager, %{
          title: "EPF",
          duty_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _spawned} =
        Duties.complete(manager, duty, %{note: "Done", next_due_by: ~D[2026-07-15]})

      {:ok, _original, replacement} =
        Duties.mark_completed_in_error(manager, done, %{reason: "redo"})

      # No next_due required, returns spawned == nil (series already ended on the replacement).
      assert {:ok, completed_replacement, nil} =
               Duties.complete(manager, replacement, %{note: "Redone"})

      assert completed_replacement.completed_at
    end

    test "a recurring original's auto-spawned successor is untouched" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity, recurring_interval: "monthly")

      {:ok, duty} =
        Duties.create_duty(manager, %{
          title: "EPF",
          duty_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, spawned} =
        Duties.complete(manager, duty, %{note: "Done", next_due_by: ~D[2026-07-15]})

      {:ok, _original, replacement} =
        Duties.mark_completed_in_error(manager, done, %{reason: "redo"})

      # The recurring successor still lives, still in the original series, unchanged.
      reloaded = Duties.get_duty!(manager, spawned.id)
      assert reloaded.completed_at == nil
      assert reloaded.closed_at == nil
      assert reloaded.series_id == done.series_id
      assert reloaded.replaces_id == nil

      # The replacement is in its own series, separate from the recurring chain.
      assert replacement.series_id != done.series_id
      assert spawned.id in Enum.map(Duties.list_series(done.series_id), & &1.id)
      refute replacement.id in Enum.map(Duties.list_series(done.series_id), & &1.id)
    end

    test "rejects a live (not completed) cycle" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, duty} =
        Duties.create_duty(manager, %{
          title: "EPF",
          duty_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      assert {:error, :not_correctable} =
               Duties.mark_completed_in_error(manager, duty, %{reason: "x"})
    end

    test "rejects a skipped cycle" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, duty} =
        Duties.create_duty(manager, %{
          title: "EPF",
          duty_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, skipped, nil} = Duties.skip(manager, duty, %{note: "drop"})

      assert {:error, :not_correctable} =
               Duties.mark_completed_in_error(manager, skipped, %{reason: "x"})
    end

    test "rejects double-correction" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, duty} =
        Duties.create_duty(manager, %{
          title: "EPF",
          duty_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _} = Duties.complete(manager, duty, %{note: "Done"})

      {:ok, original, _replacement} =
        Duties.mark_completed_in_error(manager, done, %{reason: "first"})

      assert {:error, :already_corrected} =
               Duties.mark_completed_in_error(manager, original, %{reason: "second"})
    end

    test "requires a reason" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, duty} =
        Duties.create_duty(manager, %{
          title: "EPF",
          duty_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _} = Duties.complete(manager, duty, %{note: "Done"})

      assert {:error, :note_required} =
               Duties.mark_completed_in_error(manager, done, %{reason: ""})
    end

    test "members may not correct" do
      manager = Tugas.EntitiesFixtures.manager_scope_fixture()
      member = member_scope_on_entity(manager.entity)
      type = type_fixture(manager.entity)

      {:ok, duty} =
        Duties.create_duty(manager, %{
          title: "EPF",
          duty_type_id: type.id,
          primary_assignee_id: member.user.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _} = Duties.complete(manager, duty, %{note: "Done"})

      assert :not_authorise =
               Duties.mark_completed_in_error(member, done, %{reason: "x"})
    end
  end

  describe "member assignment counts" do
    test "count_member_assignments/2 counts live primary duties and collaborations" do
      admin = entity_scope_fixture()
      member = member_scope_on_entity(admin.entity)
      type = type_fixture(admin.entity)

      {:ok, _primary} =
        Duties.create_duty(admin, %{
          title: "Led duty",
          duty_type_id: type.id,
          primary_assignee_id: member.user.id,
          due_by: ~D[2026-06-15],
          open_note: "opened"
        })

      {:ok, collab_duty} =
        Duties.create_duty(admin, %{
          title: "Collab duty",
          duty_type_id: type.id,
          primary_assignee_id: nil,
          due_by: ~D[2026-06-15],
          open_note: "opened"
        })

      {:ok, _} = Duties.update_collaborators(admin, collab_duty, [member.user.id])

      assert %{primary: 1, collaborations: 1} =
               Duties.count_member_assignments(admin, member.user.id)
    end

    test "member_assignment_counts/1 returns a per-user map for the entity" do
      admin = entity_scope_fixture()
      member = member_scope_on_entity(admin.entity)
      type = type_fixture(admin.entity)

      {:ok, _} =
        Duties.create_duty(admin, %{
          title: "Led duty",
          duty_type_id: type.id,
          primary_assignee_id: member.user.id,
          due_by: ~D[2026-06-15],
          open_note: "opened"
        })

      counts = Duties.member_assignment_counts(admin.entity)
      assert %{primary: 1, collaborations: 0} = counts[member.user.id]
    end
  end

  describe "series_neighbors/1" do
    test "returns nil neighbors for a standalone cycle" do
      {_scope, duty} = manager_duty_scope_fixture()
      assert %{previous: nil, next: nil} = Duties.series_neighbors(duty)
    end

    test "returns adjacent cycles ordered by due date" do
      {scope, duty} = recurring_primary_scope_fixture(interval: "monthly")

      assert {:ok, first, second} =
               Duties.complete(scope, duty, %{note: "Done", next_due_by: ~D[2026-02-15]})

      assert {:ok, middle, third} =
               Duties.complete(scope, second, %{note: "Done", next_due_by: ~D[2026-03-15]})

      assert %{previous: nil, next: %{id: second_id}} = Duties.series_neighbors(first)
      assert second_id == second.id

      assert %{previous: %{id: first_id}, next: %{id: third_id}} = Duties.series_neighbors(middle)
      assert first_id == first.id
      assert third_id == third.id

      assert %{previous: %{id: middle_id}, next: nil} = Duties.series_neighbors(third)
      assert middle_id == middle.id
    end
  end
end
