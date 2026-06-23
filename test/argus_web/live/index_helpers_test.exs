defmodule ArgusWeb.ObligationLive.IndexHelpersTest do
  use Argus.DataCase, async: true

  import Argus.ObligationsFixtures

  alias ArgusWeb.ObligationLive.IndexHelpers, as: Index
  alias Argus.Obligations.Urgency

  test "sorts/1 includes urgency only for live" do
    assert {"urgency", _} = List.keyfind(Index.sorts(:live), "urgency", 0)
    refute List.keyfind(Index.sorts(:completed), "urgency", 0)
  end

  test "effective_sort keeps urgency on live, downgrades elsewhere" do
    assert Index.effective_sort(:urgency, :live) == :urgency
    assert Index.effective_sort(:urgency, :completed) == :due_asc
    assert Index.effective_sort(:title, :completed) == :title
  end

  test "parse_sort whitelists with due_asc default" do
    assert Index.parse_sort("title") == :title
    assert Index.parse_sort("bogus") == :due_asc
  end

  test "load_page returns paged rows for a non-urgency sort" do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    type = type_fixture(manager.entity)

    for {title, due} <- [{"a", ~D[2026-01-01]}, {"b", ~D[2026-02-01]}, {"c", ~D[2026-03-01]}] do
      {:ok, _} =
        Argus.Obligations.create_obligation(manager, %{
          title: title,
          obligation_type_id: type.id,
          due_by: due,
          open_note: "n"
        })
    end

    today = Urgency.today_for(manager.entity.timezone)
    page = Index.load_page(manager, today, false, :live, "", :due_asc, nil)

    assert Enum.map(page.rows, & &1.obligation.title) == ["a", "b", "c"]
    assert page.end?
    assert Enum.all?(page.rows, &Map.has_key?(&1, :tier))
  end

  test "someday lifecycle: status atom, label, sorts, effective_sort" do
    assert Index.status_atom(false, :someday) == :someday
    assert Index.status_atom(true, :someday) == :my_someday
    assert Index.parse_lifecycle("someday") == :someday
    assert Index.lifecycle_label(:someday) == "Someday"

    assert {"recent", "Recently added"} = List.keyfind(Index.sorts(:someday), "recent", 0)
    refute List.keyfind(Index.sorts(:someday), "urgency", 0)
    refute List.keyfind(Index.sorts(:live), "recent", 0)

    assert Index.effective_sort(:recent, :someday) == :recent
    assert Index.effective_sort(:recent, :live) == :due_asc
    assert Index.effective_sort(:due_asc, :someday) == :recent
    assert Index.parse_sort("recent") == :recent
  end

  describe "load_page urgency on live" do
    setup do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      # reminder offset 30 days => due within 30d is due_soon, overdue is past.
      type = type_fixture(manager.entity, reminder_offsets: "30")
      today = ~D[2026-06-01]

      mk = fn title, due ->
        {:ok, o} =
          Argus.Obligations.create_obligation(manager, %{
            title: title,
            obligation_type_id: type.id,
            due_by: due,
            open_note: "n"
          })

        o
      end

      overdue = mk.("overdue", ~D[2026-05-01])
      soon = mk.("soon", ~D[2026-06-10])
      ok = mk.("ok", ~D[2026-09-01])
      far = mk.("far", ~D[2027-12-01])
      %{manager: manager, today: today, overdue: overdue, soon: soon, ok: ok, far: far}
    end

    test "ranks overdue, then due_soon, then ok by due date; far tail loads last",
         %{manager: m, today: today, overdue: o, soon: s, ok: k, far: f} do
      p1 =
        ArgusWeb.ObligationLive.IndexHelpers.load_page(m, today, false, :live, "", :urgency, nil)

      assert Enum.map(p1.rows, & &1.obligation.id) == [o.id, s.id, k.id]
      refute p1.end?

      p2 =
        ArgusWeb.ObligationLive.IndexHelpers.load_page(
          m,
          today,
          false,
          :live,
          "",
          :urgency,
          p1.cursor
        )

      assert Enum.map(p2.rows, & &1.obligation.id) == [f.id]
      assert p2.end?
    end
  end
end
