defmodule ArgusWeb.ObligationStatusBadgeTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  import ArgusWeb.ObligationStatusBadge

  alias Argus.Obligations.Obligation

  @at ~U[2026-06-23 08:00:00Z]

  test "Completed badge shows the completed date" do
    html =
      render_component(&obligation_status_badge/1,
        cycle_status: :completed,
        in_error: false,
        obligation: %Obligation{completed_at: @at}
      )

    assert html =~ "Completed"
    assert html =~ "23 Jun 2026"
    assert html =~ "bg-success"
  end

  test "Skipped badge shares the Completed layout and shows the closed date, in a different colour" do
    html =
      render_component(&obligation_status_badge/1,
        cycle_status: :skipped,
        in_error: false,
        obligation: %Obligation{closed_at: @at}
      )

    assert html =~ "Skipped"
    assert html =~ "23 Jun 2026"
    assert html =~ "bg-warning"
  end

  test "Series ended badge shows the closed date" do
    html =
      render_component(&obligation_status_badge/1,
        cycle_status: :series_ended,
        in_error: false,
        obligation: %Obligation{closed_at: @at}
      )

    assert html =~ "Series ended"
    assert html =~ "23 Jun 2026"
  end

  test "an in-error Completed badge uses the error colour" do
    html =
      render_component(&obligation_status_badge/1,
        cycle_status: :completed,
        in_error: true,
        obligation: %Obligation{completed_at: @at}
      )

    assert html =~ "bg-error"
  end
end
