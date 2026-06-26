defmodule Argus.TodosTest do
  use Argus.DataCase, async: true

  @moduletag :todos

  alias Argus.Accounts.Scope
  alias Argus.Repo
  alias Argus.Todos
  alias Argus.Todos.Todo

  import Argus.AccountsFixtures, only: [user_fixture: 0]
  import Argus.EntitiesFixtures, only: [entity_scope_fixture: 0, manager_scope_fixture: 0]
  import Argus.ObligationsFixtures, only: [member_scope_on_entity: 1, type_fixture: 1]

  describe "authorization" do
    test "list_todos/1 and get_todo/2 return :not_authorise without entity scope" do
      scope = Scope.for_user(user_fixture())
      fake_id = Ecto.UUID.generate()

      assert :not_authorise = Todos.list_todos(scope)
      assert :not_authorise = Todos.get_todo(scope, fake_id)
      assert :not_authorise = Todos.create_todo(scope, %{title: "Nope"})
    end

    test "get_todo/2 returns :not_found for unknown id" do
      scope = entity_scope_fixture()
      assert :not_found = Todos.get_todo(scope, Ecto.UUID.generate())
    end
  end

  describe "create_todo/2 and list_todos/1" do
    test "creates a todo visible to all team members" do
      creator = entity_scope_fixture()
      teammate = member_scope_on_entity(creator.entity)

      assert {:ok, todo} = Todos.create_todo(creator, %{title: "Buy supplies"})
      assert todo.title == "Buy supplies"
      assert todo.entity_id == creator.entity.id
      assert todo.created_by_id == creator.user.id
      assert is_nil(todo.completed_at)

      assert {:ok, listed} = Todos.list_todos(teammate)
      assert length(listed) == 1
      assert hd(listed).id == todo.id
    end

    test "filters open, completed, escalated, canceled, and all todos" do
      manager = manager_scope_fixture()
      type = type_fixture(manager.entity)
      {:ok, pending} = Todos.create_todo(manager, %{title: "Pending"})
      {:ok, todo} = Todos.create_todo(manager, %{title: "Complete"})
      assert {:ok, done} = Todos.toggle_complete(manager, todo)

      {:ok, to_escalate} = Todos.create_todo(manager, %{title: "Escalate me"})
      {:ok, stale} = Todos.create_todo(manager, %{title: "Cancel me"})
      stale = backdate_todo!(stale, 49)

      assert {:ok, obligation} =
               Argus.Obligations.create_obligation(manager, %{
                 title: "Escalate me",
                 obligation_type_id: type.id,
                 due_by: ~D[2026-07-01],
                 open_note: "Escalated"
               })

      assert {:ok, escalated} = Todos.record_escalation(manager, to_escalate, obligation)
      assert {:ok, canceled} = Todos.cancel_todo(manager, stale, "No longer needed")

      assert {:ok, open} = Todos.list_todos(manager, status: :open)
      assert Enum.map(open, & &1.title) == ["Pending"]

      assert {:ok, completed} = Todos.list_todos(manager, status: :completed)
      assert Enum.map(completed, & &1.title) == ["Complete"]

      assert {:ok, escalated_list} = Todos.list_todos(manager, status: :escalated)
      assert Enum.map(escalated_list, & &1.id) == [escalated.id]
      assert Todo.display_status(hd(escalated_list)) == :escalated

      assert {:ok, canceled_list} = Todos.list_todos(manager, status: :canceled)
      assert Enum.map(canceled_list, & &1.id) == [canceled.id]
      assert Todo.display_status(hd(canceled_list)) == :canceled

      assert {:ok, all} = Todos.list_todos(manager, status: :all)
      assert length(all) == 4
      refute Todo.completed?(pending)
      assert Todo.completed?(done)
    end

    test "rejects blank title" do
      scope = entity_scope_fixture()
      assert {:error, changeset} = Todos.create_todo(scope, %{title: ""})
      assert "can't be blank" in errors_on(changeset).title
    end
  end

  describe "update_todo/3" do
    test "updates title and records audit" do
      scope = entity_scope_fixture()
      {:ok, todo} = Todos.create_todo(scope, %{title: "Draft memo"})

      assert {:ok, updated} = Todos.update_todo(scope, todo, %{title: "Send memo"})
      assert updated.title == "Send memo"

      [created, updated_entry] = Todos.list_audit_logs(updated)
      assert created.action == "created"
      assert updated_entry.action == "updated"
      assert updated_entry.field == "title"
      assert updated_entry.old_value == "Draft memo"
      assert updated_entry.new_value == "Send memo"
      assert updated_entry.user_id == scope.user.id
    end
  end

  describe "toggle_complete/2" do
    test "completes and reopens with audit trail" do
      creator = entity_scope_fixture()
      finisher = member_scope_on_entity(creator.entity)
      {:ok, todo} = Todos.create_todo(creator, %{title: "Call vendor"})

      assert {:ok, completed} = Todos.toggle_complete(finisher, todo)
      assert %DateTime{} = completed.completed_at
      assert completed.completed_by_id == finisher.user.id

      logs = Todos.list_audit_logs(completed)
      assert Enum.any?(logs, &(&1.action == "completed" && &1.user_id == finisher.user.id))

      assert {:ok, reopened} = Todos.toggle_complete(creator, completed)
      assert is_nil(reopened.completed_at)
      assert Enum.any?(Todos.list_audit_logs(reopened), &(&1.action == "reopened"))
    end
  end

  describe "completed todo restrictions" do
    test "rejects edit, delete, and cancel on completed todos" do
      scope = entity_scope_fixture()
      {:ok, todo} = Todos.create_todo(scope, %{title: "Done item"})
      {:ok, completed} = Todos.toggle_complete(scope, todo)

      assert :not_found = Todos.update_todo(scope, completed, %{title: "Changed"})
      assert {:error, :not_deletable} = Todos.delete_todo(scope, completed)
      assert {:error, :not_cancelable} = Todos.cancel_todo(scope, completed, "Too late")

      assert {:ok, reopened} = Todos.toggle_complete(scope, completed)
      assert {:ok, _} = Todos.update_todo(scope, reopened, %{title: "Changed"})
    end
  end

  describe "delete_todo/2" do
    test "soft-deletes todo within 48 hours" do
      scope = entity_scope_fixture()
      {:ok, todo} = Todos.create_todo(scope, %{title: "Scratch item"})
      assert {:ok, deleted} = Todos.delete_todo(scope, todo)
      assert %DateTime{} = deleted.deleted_at
      assert {:ok, []} = Todos.list_todos(scope)

      audit = Enum.find(Todos.list_audit_logs(deleted), &(&1.action == "deleted"))
      assert audit
      assert audit.todo_id == deleted.id
      assert audit.old_value == "Scratch item"
      assert audit.user_id == scope.user.id

      assert {:ok, activity} = Todos.list_entity_audit_logs(scope)
      assert Enum.any?(activity, &(&1.action == "deleted" && &1.todo_id == deleted.id))
    end

    test "rejects delete after 48 hours" do
      scope = entity_scope_fixture()
      {:ok, todo} = Todos.create_todo(scope, %{title: "Old item"})
      todo = backdate_todo!(todo, 49)

      assert {:error, :delete_window_expired} = Todos.delete_todo(scope, todo)
      assert {:ok, [listed]} = Todos.list_todos(scope)
      assert listed.id == todo.id
    end
  end

  describe "list_entity_audit_logs/2 filtering" do
    test "filters by action" do
      scope = entity_scope_fixture()
      {:ok, a} = Todos.create_todo(scope, %{title: "Alpha"})
      {:ok, _b} = Todos.create_todo(scope, %{title: "Beta"})
      {:ok, _completed} = Todos.toggle_complete(scope, a)

      assert {:ok, logs} = Todos.list_entity_audit_logs(scope, action: "completed")
      assert Enum.all?(logs, &(&1.action == "completed"))
      assert length(logs) == 1
    end

    test "search matches todo title (ILIKE)" do
      scope = entity_scope_fixture()
      {:ok, _a} = Todos.create_todo(scope, %{title: "Refill printer"})
      {:ok, _b} = Todos.create_todo(scope, %{title: "Order coffee"})

      assert {:ok, logs} = Todos.list_entity_audit_logs(scope, search: "printer")
      assert length(logs) == 1
      assert hd(logs).todo.title == "Refill printer"
    end

    test "search matches actor email/username (ILIKE)" do
      scope = entity_scope_fixture()
      other = member_scope_on_entity(scope.entity)
      {:ok, _mine} = Todos.create_todo(scope, %{title: "Mine"})
      {:ok, _theirs} = Todos.create_todo(other, %{title: "Theirs"})

      assert {:ok, logs} = Todos.list_entity_audit_logs(scope, search: other.user.email)
      assert logs != []
      assert Enum.all?(logs, &(&1.user_id == other.user.id))
    end

    test "action and search combine" do
      scope = entity_scope_fixture()
      {:ok, a} = Todos.create_todo(scope, %{title: "Unique-needle"})
      {:ok, b} = Todos.create_todo(scope, %{title: "Other"})
      {:ok, _} = Todos.toggle_complete(scope, a)
      {:ok, _} = Todos.toggle_complete(scope, b)

      assert {:ok, logs} =
               Todos.list_entity_audit_logs(scope, action: "completed", search: "needle")

      assert length(logs) == 1
      assert hd(logs).action == "completed"
      assert hd(logs).todo.title == "Unique-needle"
    end
  end

  describe "list_entity_audit_logs_page/2" do
    test "keyset-paginates newest-first and stops at the end" do
      scope = entity_scope_fixture()
      for i <- 1..7, do: {:ok, _} = Todos.create_todo(scope, %{title: "T#{i}"})

      assert {:ok, %{rows: page1, cursor: cursor, end?: false}} =
               Todos.list_entity_audit_logs_page(scope, limit: 5)

      assert length(page1) == 5
      assert cursor

      assert {:ok, %{rows: page2, cursor: nil, end?: true}} =
               Todos.list_entity_audit_logs_page(scope, limit: 5, cursor: cursor)

      assert length(page2) == 2

      ids = Enum.map(page1 ++ page2, & &1.id)
      assert ids == Enum.uniq(ids)
    end

    test "applies action/search filters across pages" do
      scope = entity_scope_fixture()
      {:ok, a} = Todos.create_todo(scope, %{title: "Needle"})
      {:ok, _b} = Todos.create_todo(scope, %{title: "Hay"})
      {:ok, _} = Todos.toggle_complete(scope, a)

      assert {:ok, %{rows: rows, end?: true}} =
               Todos.list_entity_audit_logs_page(scope, action: "completed")

      assert Enum.all?(rows, &(&1.action == "completed"))
      assert length(rows) == 1
    end
  end

  describe "cancel_todo/3" do
    test "cancels todo after 48 hours with required note" do
      scope = entity_scope_fixture()
      {:ok, todo} = Todos.create_todo(scope, %{title: "Stale task"})
      todo = backdate_todo!(todo, 49)

      assert {:ok, canceled} = Todos.cancel_todo(scope, todo, "No longer needed")
      assert %DateTime{} = canceled.canceled_at
      assert canceled.canceled_by_id == scope.user.id
      assert {:ok, []} = Todos.list_todos(scope, status: :open)
      assert {:ok, [listed]} = Todos.list_todos(scope, status: :canceled)
      assert listed.id == canceled.id

      audit = Enum.find(Todos.list_audit_logs(canceled), &(&1.action == "canceled"))
      assert audit.new_value == "No longer needed"
    end

    test "rejects cancel within 48 hours" do
      scope = entity_scope_fixture()
      {:ok, todo} = Todos.create_todo(scope, %{title: "Fresh task"})

      assert {:error, :not_cancelable} = Todos.cancel_todo(scope, todo, "Too soon")
    end

    test "rejects blank cancel note" do
      scope = entity_scope_fixture()
      {:ok, todo} = Todos.create_todo(scope, %{title: "Stale task"})
      todo = backdate_todo!(todo, 49)

      assert {:error, :note_required} = Todos.cancel_todo(scope, todo, "")
    end
  end

  describe "record_escalation/3" do
    test "links todo to obligation and keeps it visible as escalated" do
      manager = manager_scope_fixture()
      type = type_fixture(manager.entity)
      {:ok, todo} = Todos.create_todo(manager, %{title: "Needs formal duty"})

      assert {:ok, obligation} =
               Argus.Obligations.create_obligation(manager, %{
                 title: "Needs formal duty",
                 obligation_type_id: type.id,
                 due_by: ~D[2026-07-01],
                 open_note: "Escalated from todo"
               })

      assert {:ok, escalated} = Todos.record_escalation(manager, todo, obligation)
      assert escalated.escalated_obligation_id == obligation.id
      assert %DateTime{} = escalated.escalated_at
      assert {:ok, []} = Todos.list_todos(manager, status: :open)
      assert {:ok, [listed]} = Todos.list_todos(manager, status: :escalated)
      assert listed.id == escalated.id
      assert Todo.display_status(listed) == :escalated

      audit = Enum.find(Todos.list_audit_logs(escalated), &(&1.action == "escalated"))
      assert audit.new_value == obligation.id
    end

    test "rejects escalation of completed todo" do
      manager = manager_scope_fixture()
      type = type_fixture(manager.entity)
      {:ok, todo} = Todos.create_todo(manager, %{title: "Done task"})
      {:ok, completed} = Todos.toggle_complete(manager, todo)

      assert {:ok, obligation} =
               Argus.Obligations.create_obligation(manager, %{
                 title: "Done task",
                 obligation_type_id: type.id,
                 due_by: ~D[2026-07-01],
                 open_note: "Escalated"
               })

      assert :not_found = Todos.get_todo_for_escalation(manager, completed.id)
      assert :not_found = Todos.record_escalation(manager, completed, obligation)
    end
  end

  describe "cross-user workflow" do
    test "full sequence twice for consistency" do
      for _ <- 1..2 do
        creator = entity_scope_fixture()
        teammate = member_scope_on_entity(creator.entity)

        {:ok, todo} = Todos.create_todo(creator, %{title: "Team task #{System.unique_integer()}"})
        assert {:ok, [listed]} = Todos.list_todos(teammate)
        assert listed.id == todo.id

        assert {:ok, todo} = Todos.update_todo(teammate, todo, %{title: "Updated team task"})
        assert {:ok, todo} = Todos.toggle_complete(teammate, todo)
        assert Todo.completed?(todo)

        logs = Todos.list_audit_logs(todo)
        actions = Enum.map(logs, & &1.action)
        assert "created" in actions
        assert "updated" in actions
        assert "completed" in actions

        assert {:ok, todo} = Todos.toggle_complete(creator, todo)
        assert {:ok, _} = Todos.delete_todo(creator, todo)
        assert {:ok, []} = Todos.list_todos(teammate)
      end
    end
  end

  describe "list_todos_page/2" do
    test "keyset-paginates open todos newest first" do
      scope = entity_scope_fixture()

      for i <- 1..30 do
        {:ok, todo} =
          Todos.create_todo(scope, %{
            title: "Todo #{String.pad_leading(Integer.to_string(i), 2, "0")}"
          })

        _ = stagger_todo!(todo, 30 - i)
      end

      assert {:ok, page1} = Todos.list_todos_page(scope, status: :open, limit: 25)
      assert length(page1.rows) == 25
      assert hd(page1.rows).title == "Todo 30"
      refute page1.end?

      assert {:ok, page2} =
               Todos.list_todos_page(scope,
                 status: :open,
                 limit: 25,
                 cursor: page1.cursor
               )

      assert length(page2.rows) == 5
      assert List.last(page2.rows).title == "Todo 01"
      assert page2.end?
    end

    test "limit: :all returns everything with end? true" do
      scope = entity_scope_fixture()
      {:ok, _} = Todos.create_todo(scope, %{title: "One"})
      {:ok, _} = Todos.create_todo(scope, %{title: "Two"})

      assert {:ok, page} = Todos.list_todos_page(scope, status: :open, limit: :all)
      assert length(page.rows) == 2
      assert page.end?
      assert page.cursor == nil
    end

    test "status: :all keyset-paginates across lifecycle tiers" do
      scope = entity_scope_fixture()

      # 26 open todos (tier 0) so the first page is entirely open and a second
      # page is needed to reach the completed/canceled rows.
      for i <- 1..26 do
        {:ok, t} = Todos.create_todo(scope, %{title: "open #{i}"})
        stagger_todo!(t, 100 - i)
      end

      {:ok, completed} = Todos.create_todo(scope, %{title: "completed one"})
      {:ok, _} = Todos.toggle_complete(scope, completed)

      {:ok, to_cancel} = Todos.create_todo(scope, %{title: "canceled one"})
      to_cancel = backdate_todo!(to_cancel, 72)
      {:ok, _} = Todos.cancel_todo(scope, to_cancel, "nope")

      pages = paginate_all(scope, :all)
      titles = pages |> Enum.flat_map(& &1.rows) |> Enum.map(& &1.title)

      # No crash, every tier is reachable, and no row is dropped or duplicated.
      assert length(titles) == 28
      assert length(Enum.uniq(titles)) == 28
      assert "completed one" in titles
      assert "canceled one" in titles
    end
  end

  defp paginate_all(scope, status, cursor \\ nil, acc \\ []) do
    {:ok, page} = Todos.list_todos_page(scope, status: status, cursor: cursor, limit: 25)
    acc = acc ++ [page]

    if page.end? or page.cursor == nil do
      acc
    else
      paginate_all(scope, status, page.cursor, acc)
    end
  end

  defp backdate_todo!(%Todo{} = todo, hours_ago) do
    old = DateTime.add(DateTime.utc_now(:second), -hours_ago * 3600, :second)

    todo
    |> Ecto.Changeset.change(inserted_at: old)
    |> Repo.update!()
  end

  defp stagger_todo!(%Todo{} = todo, seconds_ago) do
    old = DateTime.add(DateTime.utc_now(:second), -seconds_ago, :second)

    todo
    |> Ecto.Changeset.change(inserted_at: old)
    |> Repo.update!()
  end
end
