defmodule Argus.Obligations.EventTest do
  use ExUnit.Case, async: true

  alias Argus.Obligations.Event

  test "terminal_statuses are the closing statuses" do
    assert Event.terminal_statuses() == ["done", "cancelled", "skipped", "series_ended"]
  end

  test "changeset accepts all valid statuses" do
    for status <- ["open", "in_progress", "done", "cancelled", "skipped", "series_ended"] do
      cs = Event.changeset(%Event{}, %{status: status, note: "n"})
      assert cs.valid?, "expected #{status} to be valid"
    end
  end
end
