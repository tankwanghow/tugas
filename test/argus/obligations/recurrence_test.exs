defmodule Argus.Obligations.RecurrenceTest do
  use ExUnit.Case, async: true

  alias Argus.Obligations.Recurrence
  alias Argus.Obligations.Type

  test "next_due_suggestion monthly adds one month" do
    type = %Type{recurring_interval: "monthly"}
    assert Recurrence.next_due_suggestion(type, ~D[2026-01-15]) == ~D[2026-02-15]
  end

  test "shift_month clamps end of month" do
    type = %Type{recurring_interval: "monthly"}
    assert Recurrence.next_due_suggestion(type, ~D[2026-01-31]) == ~D[2026-02-28]
  end

  test "custom interval returns nil" do
    type = %Type{recurring_interval: "custom"}
    assert Recurrence.next_due_suggestion(type, ~D[2026-01-15]) == nil
  end

  test "none interval returns nil" do
    type = %Type{recurring_interval: "none"}
    assert Recurrence.next_due_suggestion(type, ~D[2026-01-15]) == nil
  end

  test "none is not recurring" do
    type = %Type{recurring_interval: "none"}
    refute Recurrence.recurring?(type)
  end
end