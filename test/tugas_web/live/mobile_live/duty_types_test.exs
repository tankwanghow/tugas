defmodule TugasWeb.MobileLive.DutyTypesTest do
  use TugasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @mobile_ua "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"

  setup :register_and_log_in_user

  defp mobile_conn(conn, scope) do
    conn |> log_in_user(scope.user) |> put_req_header("user-agent", @mobile_ua)
  end

  test "mobile index row shows reminder offsets (days before due)", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)

    {:ok, type} =
      Tugas.Duties.create_type(manager, %{
        "name" => "VAT Filing",
        "recurring_interval" => "monthly",
        "reminder_offsets" => "30, 7, 1"
      })

    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}/duty-types")

    row = render(element(view, "#m-type-#{type.id}"))
    assert row =~ "1,7,30"
    assert row =~ "days before due"
  end
end
