defmodule ArgusWeb.TodoLiveTest do
  use ArgusWeb.ConnCase, async: true

  @moduletag :todos

  import Phoenix.LiveViewTest
  alias Argus.Repo
  alias Argus.Todos.Todo

  import Argus.EntitiesFixtures, only: [entity_scope_fixture: 0, manager_scope_fixture: 0]
  import Argus.ObligationsFixtures, only: [member_scope_on_entity: 1, type_fixture: 1]

  @mobile_ua "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"

  defp mobile_conn(conn, user) do
    conn |> log_in_user(user) |> put_req_header("user-agent", @mobile_ua)
  end

  test "desktop todo team log page shows entity activity", %{conn: conn} do
    scope = entity_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, _} = Argus.Todos.create_todo(scope, %{title: "Logged task"})

    {:ok, view, html} = live(conn, ~p"/entities/#{scope.entity.slug}/todos/team-log")

    assert html =~ "Todo team log"
    assert has_element?(view, "#todo-team-log", "Logged task")
    assert has_element?(view, "#todo-team-log", "Created")
    refute has_element?(view, "#team-activity")
  end

  test "desktop user dropdown links to todo team log", %{conn: conn} do
    scope = entity_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}/todos")

    assert has_element?(view, "#todo-team-log-nav-link", "Todo team log")
  end

  test "mobile more menu links to todo team log", %{conn: conn} do
    scope = entity_scope_fixture()
    conn = mobile_conn(conn, scope.user)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}/todos")

    assert has_element?(view, "#m-more-todo-team-log-link", "Todo team log")
  end

  test "mobile todo team log page loads", %{conn: conn} do
    scope = entity_scope_fixture()
    conn = mobile_conn(conn, scope.user)

    {:ok, _} = Argus.Todos.create_todo(scope, %{title: "Mobile log entry"})

    {:ok, view, html} =
      live(conn, ~p"/m/#{scope.entity.slug}/todos/team-log")

    assert html =~ "Todo team log"
    assert has_element?(view, "#m-todo-team-log", "Mobile log entry")
    refute has_element?(view, "#m-team-activity")
  end

  test "desktop todos page loads with create controls", %{conn: conn} do
    scope = entity_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, html} = live(conn, ~p"/entities/#{scope.entity.slug}/todos")

    assert html =~ "Todos"
    assert has_element?(view, "#new-todo-btn")
    assert has_element?(view, "#todo-status-filter")
    assert has_element?(view, "#todos-empty")
  end

  test "completed todo only allows reopen on desktop", %{conn: conn} do
    admin = entity_scope_fixture()
    scope = member_scope_on_entity(admin.entity)
    conn = log_in_user(conn, scope.user)

    {:ok, todo} = Argus.Todos.create_todo(scope, %{title: "Restock pantry"})

    {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}/todos")

    view |> element("#todo-complete-#{todo.id}") |> render_click()
    refute has_element?(view, "#todo-#{todo.id}")

    view |> form("#todo-status-filter", %{status: "completed"}) |> render_change()
    assert has_element?(view, "#todo-badge-#{todo.id}", "Completed")
    refute has_element?(view, "#todo-actions-#{todo.id}")
    refute has_element?(view, "#todo-delete-#{todo.id}")
    refute has_element?(view, "#todo-edit-#{todo.id}")
    refute has_element?(view, "#todo-cancel-#{todo.id}")
    refute has_element?(view, "#todo-escalate-#{todo.id}")

    view |> element("#todo-complete-#{todo.id}") |> render_click()
    view |> form("#todo-status-filter", %{status: "open"}) |> render_change()
    assert has_element?(view, "#todo-#{todo.id}")
    refute has_element?(view, "#todo-badge-#{todo.id}")
  end

  test "member creates and deletes an open todo on desktop", %{conn: conn} do
    admin = entity_scope_fixture()
    scope = member_scope_on_entity(admin.entity)
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}/todos")

    view |> element("#new-todo-btn") |> render_click()
    assert has_element?(view, "#todo-modal")

    view
    |> form("#todo-form", %{"todo" => %{"title" => "Restock pantry"}})
    |> render_submit()

    assert has_element?(view, "#todos-list", "Restock pantry")

    {:ok, [todo]} = Argus.Todos.list_todos(scope)

    render_click(view, "todo_action", %{"id" => todo.id, "action" => "delete"})
    assert has_element?(view, "#todo-#{todo.id}[data-effect=deleted]")

    render_click(view, "finish_row_effect", %{"id" => todo.id})
    assert has_element?(view, "#todos-empty")
  end

  test "escape closes the todo editor modal", %{conn: conn} do
    scope = entity_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}/todos")

    view |> element("#new-todo-btn") |> render_click()
    assert has_element?(view, "#todo-modal")

    view |> element("#argus-shell") |> render_keydown()
    refute has_element?(view, "#todo-modal")
  end

  test "todo created by one user appears for another team member", %{conn: conn} do
    creator = entity_scope_fixture()
    teammate = member_scope_on_entity(creator.entity)

    {:ok, _} = Argus.Todos.create_todo(creator, %{title: "Shared task"})

    conn = log_in_user(conn, teammate.user)
    {:ok, view, _html} = live(conn, ~p"/entities/#{teammate.entity.slug}/todos")

    assert has_element?(view, "#todos-list", "Shared task")
  end

  test "mobile todos page loads with create controls", %{conn: conn} do
    scope = entity_scope_fixture()
    conn = mobile_conn(conn, scope.user)

    {:ok, view, html} = live(conn, ~p"/m/#{scope.entity.slug}/todos")

    assert html =~ "Todos"
    assert has_element?(view, "#m-new-todo-nav-link")
    assert has_element?(view, "#m-todos-nav-link")
    assert has_element?(view, "#m-new-duties-nav-link")
    assert has_element?(view, "#m-duties-nav-link")
    refute has_element?(view, "#m-new-todo-btn")
    assert has_element?(view, "#m-todos-empty")
    refute has_element?(view, "#m-more-todos-link")
  end

  test "toggle on stale id does not crash and shows not found", %{conn: conn} do
    scope = entity_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}/todos")

    fake_id = Ecto.UUID.generate()
    html = render_click(view, "toggle_complete", %{"id" => fake_id})
    assert html =~ "Todo not found"
  end

  test "mobile new todo nav opens create modal", %{conn: conn} do
    scope = entity_scope_fixture()
    conn = mobile_conn(conn, scope.user)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}/todos/new")

    assert has_element?(view, "#m-todo-modal")
    assert has_element?(view, "#m-new-todo-nav-link.text-primary")
  end

  test "status filter shows completed todos", %{conn: conn} do
    scope = entity_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, open_todo} = Argus.Todos.create_todo(scope, %{title: "Still open"})
    {:ok, done_todo} = Argus.Todos.create_todo(scope, %{title: "Already done"})
    {:ok, _} = Argus.Todos.toggle_complete(scope, done_todo)

    {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}/todos")

    assert has_element?(view, "#todo-#{open_todo.id}")
    refute has_element?(view, "#todo-#{done_todo.id}")

    view |> form("#todo-status-filter", %{status: "completed"}) |> render_change()
    refute has_element?(view, "#todo-#{open_todo.id}")
    assert has_element?(view, "#todo-#{done_todo.id}.opacity-60")

    view |> form("#todo-status-filter", %{status: "all"}) |> render_change()
    assert has_element?(view, "#todo-#{open_todo.id}")
    assert has_element?(view, "#todo-#{done_todo.id}")
  end

  test "manager sees escalate link and old todos show cancel instead of delete", %{conn: conn} do
    manager = manager_scope_fixture()
    conn = log_in_user(conn, manager.user)

    {:ok, fresh} = Argus.Todos.create_todo(manager, %{title: "Fresh todo"})
    {:ok, stale} = Argus.Todos.create_todo(manager, %{title: "Stale todo"})
    stale = backdate_todo!(stale, 49)

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}/todos")

    assert has_element?(view, "#todo-escalate-#{fresh.id}", "Duty")
    assert has_element?(view, "#todo-delete-#{fresh.id}")
    refute has_element?(view, "#todo-cancel-#{fresh.id}")

    refute has_element?(view, "#todo-delete-#{stale.id}")
    assert has_element?(view, "#todo-cancel-#{stale.id}")
  end

  test "cancel modal removes stale todo after note", %{conn: conn} do
    scope = entity_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, todo} = Argus.Todos.create_todo(scope, %{title: "Old cleanup"})
    todo = backdate_todo!(todo, 49)

    {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}/todos")

    render_click(view, "todo_action", %{"id" => todo.id, "action" => "cancel"})
    assert has_element?(view, "#todo-cancel-modal")

    view
    |> form("#todo-cancel-form", %{"cancel" => %{"note" => "No longer relevant"}})
    |> render_submit()

    assert has_element?(view, "#todos-empty")

    view |> form("#todo-status-filter", %{status: "canceled"}) |> render_change()
    assert has_element?(view, "#todo-#{todo.id}")
    assert has_element?(view, "#todo-badge-#{todo.id}", "Canceled")
  end

  test "escalate pre-fills obligation form from todo", %{conn: conn} do
    manager = manager_scope_fixture()
    type = type_fixture(manager.entity)
    conn = log_in_user(conn, manager.user)

    {:ok, todo} = Argus.Todos.create_todo(manager, %{title: "Formalize this work item"})

    {:ok, view, html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/new?from_todo=#{todo.id}")

    assert html =~ "Formalize this work item"
    assert html =~ "Escalated from todo: Formalize this work item"

    view
    |> form("#obligation-create-form", %{
      "obligation" => %{
        "title" => "Formalize this work item",
        "obligation_type_id" => type.id,
        "due_by" => "2026-07-15",
        "open_note" => "Escalated from todo: Formalize this work item"
      }
    })
    |> render_submit()

    assert {:ok, []} = Argus.Todos.list_todos(manager, status: :open)

    {:ok, todos_view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}/todos")

    todos_view |> form("#todo-status-filter", %{status: "escalated"}) |> render_change()
    assert has_element?(todos_view, "#todo-#{todo.id}")
    assert has_element?(todos_view, "#todo-badge-#{todo.id}", "Escalated")
    assert has_element?(todos_view, "#todo-view-duty-#{todo.id}", "View duty")
  end

  test "desktop todos infinite scroll appends next page", %{conn: conn} do
    scope = entity_scope_fixture()
    conn = log_in_user(conn, scope.user)

    for i <- 1..30 do
      {:ok, todo} =
        Argus.Todos.create_todo(scope, %{
          title: "Todo #{String.pad_leading(Integer.to_string(i), 2, "0")}"
        })

      _ = stagger_todo!(todo, 30 - i)
    end

    {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}/todos")

    assert view |> element("#todos-list") |> render() =~ "Todo 25"
    refute view |> element("#todos-list") |> render() =~ "Todo 01"

    render_hook(view, "load_more", %{})
    assert view |> element("#todos-list") |> render() =~ "Todo 01"
  end

  test "mobile todos infinite scroll appends next page", %{conn: conn} do
    scope = entity_scope_fixture()
    conn = mobile_conn(conn, scope.user)

    for i <- 1..30 do
      {:ok, todo} =
        Argus.Todos.create_todo(scope, %{
          title: "Todo #{String.pad_leading(Integer.to_string(i), 2, "0")}"
        })

      _ = stagger_todo!(todo, 30 - i)
    end

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}/todos")

    assert view |> element("#m-todos-list") |> render() =~ "Todo 25"
    refute view |> element("#m-todos-list") |> render() =~ "Todo 01"

    render_hook(view, "load_more", %{})
    assert view |> element("#m-todos-list") |> render() =~ "Todo 01"
  end

  test "mobile member creates a todo via new route", %{conn: conn} do
    admin = entity_scope_fixture()
    scope = member_scope_on_entity(admin.entity)
    conn = mobile_conn(conn, scope.user)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}/todos/new")

    view
    |> form("#m-todo-form", %{"todo" => %{"title" => "Mobile quick task"}})
    |> render_submit()

    assert_patch(view, ~p"/m/#{scope.entity.slug}/todos")
    assert has_element?(view, "#m-todos-list", "Mobile quick task")
    refute has_element?(view, "#m-todo-modal")
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
