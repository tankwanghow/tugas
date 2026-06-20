defmodule ArgusWeb.ObligationStatusBadgeTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  import ArgusWeb.ObligationStatusBadge

  test "renders a Skipped badge" do
    html = render_component(&obligation_status_badge/1, cycle_status: :skipped, in_error: false)
    assert html =~ "Skipped"
  end

  test "renders a Series ended badge" do
    html =
      render_component(&obligation_status_badge/1, cycle_status: :series_ended, in_error: false)

    assert html =~ "Series ended"
  end
end
