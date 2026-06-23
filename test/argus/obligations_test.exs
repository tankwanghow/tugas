defmodule Argus.ObligationsTest do
  use Argus.DataCase, async: true

  alias Argus.Obligations

  import Argus.EntitiesFixtures, only: [manager_scope_fixture: 0, member_scope_fixture: 0]
  import Argus.ObligationsFixtures

  describe "create_obligation/2" do
    test "creates obligation, open event, snapshots type rules, and open note" do
      scope = manager_scope_fixture()

      type = type_fixture(scope.entity, complete_documents: "receipt")

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
      assert is_nil(obligation.completed_at)
      assert is_nil(obligation.closed_at)
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

    test "allows creating without a primary assignee" do
      scope = manager_scope_fixture()
      type = type_fixture(scope.entity)

      attrs = %{
        title: "Unassigned filing",
        obligation_type_id: type.id,
        primary_assignee_id: nil,
        due_by: ~D[2026-06-20],
        open_note: "Needs an owner"
      }

      assert {:ok, obligation} = Obligations.create_obligation(scope, attrs)
      assert is_nil(obligation.primary_assignee_id)
    end

    test "rejects a title longer than 60 characters" do
      scope = manager_scope_fixture()
      type = type_fixture(scope.entity)

      attrs = %{
        title: String.duplicate("x", 61),
        obligation_type_id: type.id,
        due_by: ~D[2026-01-15],
        open_note: "open"
      }

      assert {:error, changeset} = Obligations.create_obligation(scope, attrs)
      assert "should be at most 60 character(s)" in errors_on(changeset).title
    end

    test "requires an open note" do
      scope = manager_scope_fixture()
      type = type_fixture(scope.entity)
      assignee = member_fixture(scope.entity)

      attrs = %{
        title: "EPF Jan",
        obligation_type_id: type.id,
        primary_assignee_id: assignee.id,
        due_by: ~D[2026-01-15]
      }

      assert {:error, :note_required} = Obligations.create_obligation(scope, attrs)
    end
  end

  describe "update_obligation/3 — audit log" do
    test "does not write a 'someday' audit row when editing a dated obligation" do
      scope = manager_scope_fixture()
      type = type_fixture(scope.entity)

      {:ok, obligation} =
        Obligations.create_obligation(scope, %{
          title: "Original title",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      assert {:ok, _updated} =
               Obligations.update_obligation(scope, obligation, %{title: "Updated title"})

      fields = Obligations.list_audit_logs(obligation) |> Enum.map(& &1.field)
      refute "someday" in fields
      assert "title" in fields
    end
  end

  describe "completed-in-error schema" do
    test "new correction fields default to nil on a created obligation" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-30],
          open_note: "open"
        })

      assert obligation.completed_in_error_at == nil
      assert obligation.completed_in_error_by_id == nil
      assert obligation.completed_in_error_reason == nil
      assert obligation.replaces_id == nil
      assert obligation.replaced_by_id == nil
    end
  end

  describe "start_progress/3" do
    test "creates in_progress event with note" do
      {scope, obligation} = assigned_member_scope_fixture()

      assert {:ok, event} =
               Obligations.start_progress(scope, obligation, %{note: "Gathering documents"})

      assert event.status == "in_progress"
      assert event.note == "Gathering documents"
    end

    test "requires a progress note" do
      {scope, obligation} = assigned_member_scope_fixture()
      assert {:error, :note_required} = Obligations.start_progress(scope, obligation, %{})
    end

    test "allows multiple in_progress updates on a live cycle" do
      {scope, obligation} = assigned_member_scope_fixture()
      assert {:ok, first} = Obligations.start_progress(scope, obligation, %{note: "Started"})
      assert {:ok, second} = Obligations.start_progress(scope, obligation, %{note: "Halfway"})

      assert first.status == "in_progress"
      assert second.status == "in_progress"
      assert first.id != second.id

      in_progress =
        Obligations.list_events(obligation)
        |> Enum.filter(&(&1.status == "in_progress"))

      assert length(in_progress) == 2
    end

    test "rejects a progress update once the cycle is done" do
      {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")

      {:ok, done, _spawned} =
        Obligations.complete(scope, obligation, %{note: "Done", next_due_by: ~D[2026-02-15]})

      assert {:error, :not_live} = Obligations.start_progress(scope, done, %{note: "Too late"})
    end
  end

  describe "complete/3" do
    test "marks done, stamps completed_at, and spawns next when recurring" do
      {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")

      assert {:ok, done_obligation, new_obligation} =
               Obligations.complete(scope, obligation, %{
                 note: "Filed on time",
                 next_due_by: ~D[2026-02-15]
               })

      assert done_obligation.completed_at
      done_event = Obligations.latest_event(done_obligation)
      assert done_event.status == "done"
      assert new_obligation.due_by == ~D[2026-02-15]
      assert new_obligation.series_id == obligation.series_id
    end

    test "spawned next cycle inherits the completed cycle's opening note" do
      {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")

      assert {:ok, _done, spawned} =
               Obligations.complete(scope, obligation, %{
                 note: "Filed on time",
                 next_due_by: ~D[2026-02-15]
               })

      open_event = Obligations.latest_event(spawned)
      assert open_event.status == "open"
      assert open_event.note == "Recurring task opened"
    end

    test "requires next_due_by for a recurring, not-ended series" do
      {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")

      assert {:error, :next_due_required} =
               Obligations.complete(scope, obligation, %{note: "Done"})
    end

    test "requires a completion note" do
      {scope, obligation} = assigned_member_scope_fixture()
      assert {:error, :note_required} = Obligations.complete(scope, obligation, %{})
    end

    test "is idempotent — a second Done on the same cycle is rejected" do
      {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")

      assert {:ok, done_obligation, _} =
               Obligations.complete(scope, obligation, %{
                 note: "Done",
                 next_due_by: ~D[2026-02-15]
               })

      assert {:error, :not_live} =
               Obligations.complete(scope, done_obligation, %{
                 note: "Again",
                 next_due_by: ~D[2026-03-15]
               })
    end
  end

  describe "skip/3" do
    test "one-off skip closes the cycle with a skipped event, no successor" do
      {scope, obligation} = manager_obligation_scope_fixture()

      assert {:ok, closed, nil} = Obligations.skip(scope, obligation, %{note: "drop it"})
      assert closed.closed_at
      assert is_nil(closed.completed_at)

      events = Obligations.list_events(closed)
      assert Enum.any?(events, &(&1.status == "skipped" and &1.note == "drop it"))

      assert Obligations.list_obligations(scope, status: :live)
             |> Enum.all?(&(&1.id != closed.id))
    end

    test "recurring skip requires next_due_by and spawns the next cycle" do
      {scope, obligation} = recurring_manager_scope_fixture(interval: "monthly")

      assert {:error, :next_due_required} = Obligations.skip(scope, obligation, %{note: "skip"})

      assert {:ok, closed, %Argus.Obligations.Obligation{} = spawned} =
               Obligations.skip(scope, obligation, %{note: "skip", next_due_by: ~D[2026-08-01]})

      assert closed.closed_at
      assert spawned.series_id == closed.series_id
      assert is_nil(spawned.closed_at) and is_nil(spawned.completed_at)
    end

    test "skip requires a note" do
      {scope, obligation} = manager_obligation_scope_fixture()
      assert {:error, _} = Obligations.skip(scope, obligation, %{note: ""})
    end

    test "is idempotent — a second skip on the same cycle is rejected" do
      {scope, obligation} = recurring_manager_scope_fixture(interval: "monthly")

      assert {:ok, closed, _} =
               Obligations.skip(scope, obligation, %{
                 note: "Skip",
                 next_due_by: ~D[2026-02-15]
               })

      assert {:error, :not_live} =
               Obligations.skip(scope, closed, %{
                 note: "Again",
                 next_due_by: ~D[2026-03-15]
               })
    end
  end

  describe "complete/skip on a dateless cycle" do
    test "completing a dateless recurring duty needs no next_due and spawns nothing" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity, recurring_interval: "monthly")

      {:ok, ob} =
        Obligations.create_obligation(manager, %{
          title: "Someday recurring",
          obligation_type_id: type.id,
          someday: true,
          open_note: "n"
        })

      assert ob.due_by == nil
      assert {:ok, _completed, nil} = Obligations.complete(manager, ob, %{note: "done"})
    end
  end

  describe "end_series/3" do
    test "requires a reason" do
      {scope, obligation} = recurring_manager_scope_fixture(interval: "monthly")
      assert {:error, :note_required} = Obligations.end_series(scope, obligation, %{})
    end

    test "stamps closed_at + series_ended_at with a series_ended event" do
      {scope, obligation} = recurring_manager_scope_fixture(interval: "monthly")

      assert {:ok, ended} =
               Obligations.end_series(scope, obligation, %{note: "Client left"})

      assert ended.closed_at
      assert ended.series_ended_at

      events = Obligations.list_events(ended)
      assert Enum.any?(events, &(&1.status == "series_ended"))
      assert Obligations.latest_event(ended).note == "Client left"
      assert {:error, :not_live} = Obligations.complete(scope, ended, %{note: "Too late"})
    end
  end

  describe "Obligation.changeset/2" do
    alias Argus.Obligations.Obligation
    alias Argus.Repo

    test "requires due_by normally" do
      cs =
        Obligation.changeset(%Obligation{}, %{
          title: "t",
          obligation_type_id: Ecto.UUID.generate()
        })

      refute cs.valid?
      assert %{due_by: ["can't be blank"]} = errors_on(cs)
    end

    test "someday=true makes due_by optional and force-nils it" do
      cs =
        Obligation.changeset(%Obligation{}, %{
          title: "t",
          obligation_type_id: Ecto.UUID.generate(),
          due_by: ~D[2026-01-01],
          someday: true
        })

      refute Keyword.has_key?(cs.errors, :due_by)
      assert Ecto.Changeset.get_field(cs, :due_by) == nil
    end

    test "translates one-live-cycle-per-series unique constraint" do
      {_scope, obligation} = recurring_primary_scope_fixture()

      duplicate =
        %Obligation{
          entity_id: obligation.entity_id,
          series_id: obligation.series_id,
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
          due_by: ~D[2026-06-30],
          open_note: "Live"
        })

      {:ok, completed} =
        Obligations.create_obligation(manager, %{
          title: "EPF Done",
          obligation_type_id: type_fixture(manager.entity).id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-05-30],
          open_note: "Done cycle"
        })

      assert {:ok, completed, _} =
               Obligations.complete(member_scope, completed, %{
                 note: "Completed",
                 next_due_by: nil
               })

      {:ok, skipped} =
        Obligations.create_obligation(manager, %{
          title: "EPF Skipped",
          obligation_type_id: type_fixture(manager.entity).id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-04-30],
          open_note: "Skip cycle"
        })

      assert {:ok, _, nil} =
               Obligations.skip(manager, skipped, %{note: "Superseded"})

      live_ids = manager |> Obligations.list_obligations(status: :live) |> Enum.map(& &1.id)

      completed_ids =
        manager |> Obligations.list_obligations(status: :completed) |> Enum.map(& &1.id)

      skipped_ids =
        manager |> Obligations.list_obligations(status: :skipped) |> Enum.map(& &1.id)

      assert live_obligation.id in live_ids
      refute completed.id in live_ids
      assert completed.id in completed_ids
      assert skipped.id in skipped_ids

      assert [found] = Obligations.list_obligations(manager, status: :all, query: "done")
      assert found.id == completed.id

      {:ok, other_live} =
        Obligations.create_obligation(manager, %{
          title: "Other Live",
          obligation_type_id: type_fixture(manager.entity).id,
          primary_assignee_id: manager.user.id,
          due_by: ~D[2026-07-01],
          open_note: "Other"
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

    test "my_skipped and my_all scope to the user across lifecycles" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)
      type = type_fixture(manager.entity)

      {:ok, mine_live} =
        Obligations.create_obligation(manager, %{
          title: "Mine Live",
          obligation_type_id: type.id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-06-30],
          open_note: "live"
        })

      {:ok, mine_to_skip} =
        Obligations.create_obligation(manager, %{
          title: "Mine Skip",
          obligation_type_id: type.id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-05-30],
          open_note: "skip"
        })

      assert {:ok, mine_skipped, nil} =
               Obligations.skip(manager, mine_to_skip, %{note: "superseded"})

      {:ok, others} =
        Obligations.create_obligation(manager, %{
          title: "Theirs Skip",
          obligation_type_id: type.id,
          primary_assignee_id: manager.user.id,
          due_by: ~D[2026-05-15],
          open_note: "skip"
        })

      assert {:ok, others_skipped, nil} = Obligations.skip(manager, others, %{note: "nope"})

      my_skipped =
        member_scope |> Obligations.list_obligations(status: :my_skipped) |> Enum.map(& &1.id)

      assert mine_skipped.id in my_skipped
      refute others_skipped.id in my_skipped

      my_all = member_scope |> Obligations.list_obligations(status: :my_all) |> Enum.map(& &1.id)
      assert mine_live.id in my_all
      assert mine_skipped.id in my_all
      refute others_skipped.id in my_all
    end
  end

  describe "list_unassigned/1 and list_recently_completed/1" do
    test "list_unassigned returns live obligations with no primary assignee" do
      manager = manager_scope_fixture()
      type = type_fixture(manager.entity)
      assignee = member_fixture(manager.entity)

      {:ok, unassigned} =
        Obligations.create_obligation(manager, %{
          title: "Needs owner",
          obligation_type_id: type.id,
          primary_assignee_id: nil,
          due_by: ~D[2026-06-20],
          open_note: "Unassigned"
        })

      {:ok, _assigned} =
        Obligations.create_obligation(manager, %{
          title: "Has owner",
          obligation_type_id: type.id,
          primary_assignee_id: assignee.id,
          due_by: ~D[2026-06-21],
          open_note: "Assigned"
        })

      ids = manager |> Obligations.list_unassigned() |> Enum.map(& &1.id)
      assert unassigned.id in ids
      assert length(ids) == 1
    end

    test "list_recently_completed returns obligations completed within 14 days" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)
      type = type_fixture(manager.entity)

      {:ok, recent} =
        Obligations.create_obligation(manager, %{
          title: "Just done",
          obligation_type_id: type.id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-06-01],
          open_note: "Recent"
        })

      assert {:ok, _, _} =
               Obligations.complete(member_scope, recent, %{note: "Done", next_due_by: nil})

      ids = manager |> Obligations.list_recently_completed() |> Enum.map(& &1.id)
      assert recent.id in ids
    end

    test "my_live excludes unassigned obligations for members" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)
      type = type_fixture(manager.entity)

      {:ok, unassigned} =
        Obligations.create_obligation(manager, %{
          title: "Nobody assigned",
          obligation_type_id: type.id,
          primary_assignee_id: nil,
          due_by: ~D[2026-06-20],
          open_note: "Nobody"
        })

      my_live_ids =
        member_scope |> Obligations.list_obligations(status: :my_live) |> Enum.map(& &1.id)

      refute unassigned.id in my_live_ids
    end
  end

  describe "event_summaries_for/1" do
    test "returns event count and latest event with status_by" do
      {scope, obligation} = assigned_member_scope_fixture()

      assert {:ok, _} =
               Obligations.start_progress(scope, obligation, %{note: "Working on it"})

      summaries = Obligations.event_summaries_for([obligation])
      summary = Map.fetch!(summaries, obligation.id)

      assert summary.event_count == 2
      assert summary.latest_event.status == "in_progress"
      assert summary.latest_event.status_by.email == scope.user.email
    end
  end

  describe "live/1" do
    test "includes active incomplete obligations only" do
      {_scope, obligation} = obligation_fixture(manager_scope_fixture())

      assert [_] =
               Obligations.live()
               |> Argus.Repo.all()
               |> Enum.filter(&(&1.id == obligation.id))

      obligation
      |> Ecto.Changeset.change(completed_at: DateTime.utc_now(:second))
      |> Argus.Repo.update!()

      refute Enum.any?(Obligations.live() |> Argus.Repo.all(), &(&1.id == obligation.id))
    end
  end

  describe "list_obligations_page/2" do
    setup do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      mk = fn title, due ->
        {:ok, o} =
          Obligations.create_obligation(manager, %{
            title: title,
            obligation_type_id: type.id,
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
      page1 = Obligations.list_obligations_page(m, status: :live, sort: :due_asc, limit: 2)
      assert Enum.map(page1.rows, & &1.id) == [b.id, c.id]
      refute page1.end?

      page2 =
        Obligations.list_obligations_page(m,
          status: :live,
          sort: :due_asc,
          limit: 2,
          cursor: page1.cursor
        )

      assert Enum.map(page2.rows, & &1.id) == [a.id]
      assert page2.end?
    end

    test "sorts due_desc and title", %{manager: m, a: a, b: b, c: c} do
      desc = Obligations.list_obligations_page(m, status: :live, sort: :due_desc, limit: 10)
      assert Enum.map(desc.rows, & &1.id) == [a.id, c.id, b.id]

      title = Obligations.list_obligations_page(m, status: :live, sort: :title, limit: 10)
      assert Enum.map(title.rows, & &1.id) == [a.id, b.id, c.id]
    end

    test "search filters by title in SQL", %{manager: m, b: b} do
      page = Obligations.list_obligations_page(m, status: :live, query: "brav")
      assert Enum.map(page.rows, & &1.id) == [b.id]
    end

    test "due_before and due_after bound the window", %{manager: m, b: b, c: c, a: a} do
      before =
        Obligations.list_obligations_page(m,
          status: :live,
          sort: :due_asc,
          due_before: ~D[2026-02-15],
          limit: 10
        )

      assert Enum.map(before.rows, & &1.id) == [b.id, c.id]

      after_ =
        Obligations.list_obligations_page(m,
          status: :live,
          sort: :due_asc,
          due_after: ~D[2026-02-15],
          limit: 10
        )

      assert Enum.map(after_.rows, & &1.id) == [a.id]
    end

    test "limit: :all returns everything with end? true", %{manager: m} do
      page = Obligations.list_obligations_page(m, status: :live, sort: :due_asc, limit: :all)
      assert length(page.rows) == 3
      assert page.end?
      assert page.cursor == nil
    end

    test "my_* status scopes to the user's work and still applies the SQL search", %{manager: m} do
      member = member_scope_on_entity(m.entity)
      type = type_fixture(m.entity)

      mk = fn title, assignee_id ->
        {:ok, o} =
          Obligations.create_obligation(m, %{
            title: title,
            obligation_type_id: type.id,
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
      # search drops "Annual audit", leaving only the member's VAT obligation.
      page = Obligations.list_obligations_page(member, status: :my_live, query: "vat")
      assert Enum.map(page.rows, & &1.id) == [mine.id]
    end
  end

  describe "list_obligations_page/2 — someday + nullable keyset" do
    setup do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      dated =
        for {t, d} <- [{"Dated A", ~D[2026-02-01]}, {"Dated B", ~D[2026-03-01]}] do
          {:ok, o} =
            Obligations.create_obligation(manager, %{
              title: t,
              obligation_type_id: type.id,
              due_by: d,
              open_note: "n"
            })

          o
        end

      someday =
        for t <- ["Someday X", "Someday Y", "Someday Z"] do
          {:ok, o} =
            Obligations.create_obligation(manager, %{
              title: t,
              obligation_type_id: type.id,
              someday: true,
              open_note: "n"
            })

          o
        end

      %{manager: manager, dated: dated, someday: someday}
    end

    test "live excludes dateless; someday returns only dateless", %{
      manager: m,
      dated: dated,
      someday: someday
    } do
      live = Obligations.list_obligations_page(m, status: :live, limit: :all)

      assert Enum.map(live.rows, & &1.id) |> Enum.sort() ==
               Enum.map(dated, & &1.id) |> Enum.sort()

      sd = Obligations.list_obligations_page(m, status: :someday, sort: :recent, limit: :all)

      assert Enum.map(sd.rows, & &1.id) |> Enum.sort() ==
               Enum.map(someday, & &1.id) |> Enum.sort()
    end

    test "recent sort orders newest-first with stable keyset paging", %{
      manager: m,
      someday: someday
    } do
      all_ids = Enum.map(someday, & &1.id) |> Enum.sort()
      p1 = Obligations.list_obligations_page(m, status: :someday, sort: :recent, limit: 2)
      assert length(p1.rows) == 2
      assert p1.cursor != nil

      p2 =
        Obligations.list_obligations_page(m,
          status: :someday,
          sort: :recent,
          limit: 2,
          cursor: p1.cursor
        )

      assert length(p2.rows) == 1
      assert p2.end?
      paged_ids = (Enum.map(p1.rows, & &1.id) ++ Enum.map(p2.rows, & &1.id)) |> Enum.sort()
      assert paged_ids == all_ids
    end

    test "completed date sort places dateless cycles last (NULLS LAST)", %{
      manager: m,
      dated: [da, _db],
      someday: [sx | _]
    } do
      # complete one dated and one dateless cycle
      {:ok, _, _} = Obligations.complete(m, da, %{note: "d"})
      {:ok, _, _} = Obligations.complete(m, sx, %{note: "d"})

      page = Obligations.list_obligations_page(m, status: :completed, sort: :due_asc, limit: :all)
      ids = Enum.map(page.rows, & &1.id)
      assert List.last(ids) == sx.id
    end

    test ":my_someday scopes to primary-assignee only", %{manager: manager} do
      member = member_scope_on_entity(manager.entity)
      type = type_fixture(manager.entity)

      {:ok, member_duty} =
        Obligations.create_obligation(manager, %{
          title: "Member Someday",
          obligation_type_id: type.id,
          primary_assignee_id: member.user.id,
          someday: true,
          open_note: "n"
        })

      # duty assigned to nobody — should NOT appear in member's :my_someday
      {:ok, _other_duty} =
        Obligations.create_obligation(manager, %{
          title: "Other Someday",
          obligation_type_id: type.id,
          someday: true,
          open_note: "n"
        })

      result =
        Obligations.list_obligations_page(member, status: :my_someday, sort: :recent, limit: :all)

      assert Enum.map(result.rows, & &1.id) == [member_duty.id]
    end
  end

  describe "mark_completed_in_error/3" do
    test "flags the done cycle and spawns a standalone one-off replacement" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      member = member_scope_on_entity(manager.entity)
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF Jan",
          obligation_type_id: type.id,
          primary_assignee_id: member.user.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _spawned} = Obligations.complete(manager, obligation, %{note: "Done"})

      assert {:ok, original, replacement} =
               Obligations.mark_completed_in_error(manager, done, %{reason: "Wrong figures filed"})

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
      open_event = Obligations.latest_event(replacement)
      assert open_event.status == "open"
      assert open_event.note == "Wrong figures filed"

      # an audit row was written on the original
      assert Enum.any?(
               Obligations.list_audit_logs(original),
               &(&1.field == "completed_in_error" and &1.new_value == "Wrong figures filed")
             )
    end

    test "replacement_due_by overrides the inherited due date" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _} = Obligations.complete(manager, obligation, %{note: "Done"})

      assert {:ok, _original, replacement} =
               Obligations.mark_completed_in_error(manager, done, %{
                 reason: "redo",
                 replacement_due_by: ~D[2026-07-01]
               })

      assert replacement.due_by == ~D[2026-07-01]
    end

    test "a blank replacement_due_by falls back to the original's due date" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _} = Obligations.complete(manager, obligation, %{note: "Done"})

      # A cleared date field submits "" — must not crash; falls back to original due_by.
      assert {:ok, _original, replacement} =
               Obligations.mark_completed_in_error(manager, done, %{
                 reason: "redo",
                 replacement_due_by: ""
               })

      assert replacement.due_by == ~D[2026-06-15]
    end

    test "completing the one-off replacement does not require next_due and does not spawn" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      # recurring type — but the replacement must still behave as a one-off
      type = type_fixture(manager.entity, recurring_interval: "monthly")

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _spawned} =
        Obligations.complete(manager, obligation, %{note: "Done", next_due_by: ~D[2026-07-15]})

      {:ok, _original, replacement} =
        Obligations.mark_completed_in_error(manager, done, %{reason: "redo"})

      # No next_due required, returns spawned == nil (series already ended on the replacement).
      assert {:ok, completed_replacement, nil} =
               Obligations.complete(manager, replacement, %{note: "Redone"})

      assert completed_replacement.completed_at
    end

    test "a recurring original's auto-spawned successor is untouched" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity, recurring_interval: "monthly")

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, spawned} =
        Obligations.complete(manager, obligation, %{note: "Done", next_due_by: ~D[2026-07-15]})

      {:ok, _original, replacement} =
        Obligations.mark_completed_in_error(manager, done, %{reason: "redo"})

      # The recurring successor still lives, still in the original series, unchanged.
      reloaded = Obligations.get_obligation!(manager, spawned.id)
      assert reloaded.completed_at == nil
      assert reloaded.closed_at == nil
      assert reloaded.series_id == done.series_id
      assert reloaded.replaces_id == nil

      # The replacement is in its own series, separate from the recurring chain.
      assert replacement.series_id != done.series_id
      assert spawned.id in Enum.map(Obligations.list_series(done.series_id), & &1.id)
      refute replacement.id in Enum.map(Obligations.list_series(done.series_id), & &1.id)
    end

    test "rejects a live (not completed) cycle" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      assert {:error, :not_correctable} =
               Obligations.mark_completed_in_error(manager, obligation, %{reason: "x"})
    end

    test "rejects a skipped cycle" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, skipped, nil} = Obligations.skip(manager, obligation, %{note: "drop"})

      assert {:error, :not_correctable} =
               Obligations.mark_completed_in_error(manager, skipped, %{reason: "x"})
    end

    test "rejects double-correction" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _} = Obligations.complete(manager, obligation, %{note: "Done"})

      {:ok, original, _replacement} =
        Obligations.mark_completed_in_error(manager, done, %{reason: "first"})

      assert {:error, :already_corrected} =
               Obligations.mark_completed_in_error(manager, original, %{reason: "second"})
    end

    test "requires a reason" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _} = Obligations.complete(manager, obligation, %{note: "Done"})

      assert {:error, :note_required} =
               Obligations.mark_completed_in_error(manager, done, %{reason: ""})
    end

    test "members may not correct" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      member = member_scope_on_entity(manager.entity)
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          primary_assignee_id: member.user.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _} = Obligations.complete(manager, obligation, %{note: "Done"})

      assert :not_authorise =
               Obligations.mark_completed_in_error(member, done, %{reason: "x"})
    end
  end
end
