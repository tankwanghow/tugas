defmodule TugasWeb.DutyTypeLiveTest do
  use TugasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tugas.DutiesFixtures

  setup :register_and_log_in_user

  test "escape closes the type editor modal", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duty-types")

    view |> element("#new-type-btn") |> render_click()
    assert has_element?(view, "#type-modal")

    view |> element("#tugas-shell") |> render_keydown()
    refute has_element?(view, "#type-modal")
  end

  test "manager creates a custom type via the modal", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duty-types")

    assert has_element?(view, "#new-type-btn")

    view |> element("#new-type-btn") |> render_click()
    assert has_element?(view, "#type-modal")

    view
    |> form("#type-form", %{
      "type" => %{
        "name" => "GST Return",
        "recurring_interval" => "quarterly",
        "reminder_offsets" => "30,7"
      }
    })
    |> render_submit()

    assert has_element?(view, "#types", "GST Return")
  end

  test "manager can clone a type", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)

    [epf | _] =
      Tugas.Duties.list_types(manager)
      |> Enum.filter(&(&1.name == "EPF Monthly"))

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duty-types")

    view |> element("#type-#{epf.id} button", "Clone") |> render_click()
    assert has_element?(view, "#type-form")

    view |> form("#type-form", %{"type" => %{}}) |> render_submit()
    assert has_element?(view, "#types", "EPF Monthly (copy)")
  end

  test "index row shows reminder offsets (days before due)", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)

    {:ok, type} =
      Tugas.Duties.create_type(manager, %{
        "name" => "VAT Filing",
        "recurring_interval" => "monthly",
        "reminder_offsets" => "30, 7, 1"
      })

    # normalized canonical form: deduped, sorted ascending, no spaces.
    assert type.reminder_offsets == "1,7,30"

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}/duty-types")

    row = render(element(view, "#type-#{type.id}"))
    assert row =~ "1,7,30"
    assert row =~ "days before due"
  end

  test "index row omits reminder offsets when none are set", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)

    {:ok, type} =
      Tugas.Duties.create_type(manager, %{
        "name" => "Ad-hoc Task",
        "recurring_interval" => "none",
        "reminder_offsets" => ""
      })

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}/duty-types")

    refute render(element(view, "#type-#{type.id}")) =~ "days before due"
  end

  test "member cannot see management actions", %{conn: conn} do
    member = member_scope_on_entity(Tugas.EntitiesFixtures.manager_scope_fixture().entity)
    conn = log_in_user(conn, member.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{member.entity.slug}/duty-types")

    refute has_element?(view, "#new-type-btn")
  end
end
