defmodule TugasWeb.MobileLive.DashboardTest do
  use TugasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tugas.DutiesFixtures

  alias Tugas.Duties
  alias Tugas.Todos

  @mobile_ua "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"

  setup :register_and_log_in_user

  defp mobile_conn(conn, scope) do
    conn |> log_in_user(scope.user) |> put_req_header("user-agent", @mobile_ua)
  end

  test "renders calendar and todos preview", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)

    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}")

    assert has_element?(view, "#duty-calendar")
    assert has_element?(view, "#dashboard-todos")
    assert has_element?(view, "#m-dashboard")
  end

  test "duty appears on its due date cell", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)
    type = type_fixture(manager.entity)
    due = ~D[2026-06-18]

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "Tax filing",
        duty_type_id: type.id,
        due_by: due,
        open_note: "open"
      })

    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}")

    assert has_element?(view, "#calendar-day-#{due} #duty-chip-#{duty.id}", "Tax filing")
  end

  test "duty chip links to mobile show", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)
    type = type_fixture(manager.entity)
    due = ~D[2026-06-18]

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "Mobile link",
        duty_type_id: type.id,
        due_by: due,
        open_note: "open"
      })

    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}")

    assert has_element?(
             view,
             "#duty-chip-#{duty.id}[href='/m/#{manager.entity.slug}/duties/#{duty.id}']"
           )
  end

  test "someday duty appears in someday panel", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)
    type = type_fixture(manager.entity)

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "No date task",
        duty_type_id: type.id,
        someday: true,
        open_note: "open"
      })

    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}")

    assert has_element?(view, "#m-dashboard-someday #someday-panel-duty-chip-#{duty.id}")
  end

  test "open todo can be completed", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)

    {:ok, todo} = Todos.create_todo(manager, %{title: "Buy milk"})

    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}")

    assert has_element?(view, "#dashboard-todo-#{todo.id}", "Buy milk")

    view |> element("#dashboard-todo-complete-#{todo.id}") |> render_click()
    render_click(view, "finish_row_effect", %{"id" => todo.id})

    refute has_element?(view, "#dashboard-todo-#{todo.id}")
    assert has_element?(view, "#dashboard-completed-todo-#{todo.id}", "Buy milk")
  end

  test "completing a todo backfills the open preview", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)

    for n <- 1..12 do
      {:ok, _} =
        Todos.create_todo(manager, %{title: "Todo #{String.pad_leading("#{n}", 2, "0")}"})
    end

    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}")

    open_ids_before = dashboard_open_todo_ids(view)
    assert length(open_ids_before) == 11

    to_complete_id = List.last(open_ids_before)

    view |> element("#dashboard-todo-complete-#{to_complete_id}") |> render_click()
    render_click(view, "finish_row_effect", %{"id" => to_complete_id})

    open_ids_after = dashboard_open_todo_ids(view)
    assert length(open_ids_after) == 11
    refute to_complete_id in open_ids_after
  end

  test "day overflow opens modal", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)
    type = type_fixture(manager.entity)
    due = ~D[2026-06-22]

    for title <- ["One", "Two", "Three"] do
      {:ok, _duty} =
        Duties.create_duty(manager, %{
          title: title,
          duty_type_id: type.id,
          due_by: due,
          open_note: "open"
        })
    end

    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}")

    assert has_element?(view, "#calendar-day-more-#{due}", "+1 more")

    view |> element("#calendar-day-more-#{due}") |> render_click()
    assert has_element?(view, "#day-modal")
  end

  test "someday panel lists all duties without overflow chip", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)
    type = type_fixture(manager.entity)

    duties =
      for n <- 1..7 do
        {:ok, duty} =
          Duties.create_duty(manager, %{
            title: "Someday #{n}",
            duty_type_id: type.id,
            someday: true,
            open_note: "open"
          })

        duty
      end

    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}")

    refute has_element?(view, "#someday-more")
    refute has_element?(view, "#someday-strip")

    for duty <- duties do
      assert has_element?(
               view,
               "#m-dashboard-someday #someday-panel-duty-chip-#{duty.id}",
               duty.title
             )
    end
  end

  test "swipe carousel renders someday, calendar, and todos panels", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)

    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}")

    assert has_element?(view, "#m-dashboard-swipe")
    assert has_element?(view, "#m-dashboard-someday")
    assert has_element?(view, "#duty-calendar")
    assert has_element?(view, "#dashboard-todos")
    assert has_element?(view, "#m-dashboard-go-someday", "Someday")
    assert has_element?(view, "#m-dashboard-go-todos", "Todos")
  end

  defp dashboard_open_todo_ids(view) do
    ~r/id="dashboard-todo-([0-9a-f-]{36})"/
    |> Regex.scan(render(view))
    |> Enum.map(&List.last/1)
    |> Enum.uniq()
  end
end
