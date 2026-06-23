defmodule Argus.Obligations.Recurrence do
  @moduledoc """
  Recurring interval helpers for obligation types.
  """

  alias Argus.Obligations.Type

  @intervals ~w(none weekly every_two_weeks monthly quarterly semiannual annual custom)

  def intervals, do: @intervals

  def recurring?(%Type{recurring_interval: "none"}), do: false
  def recurring?(%Type{}), do: true

  def next_due_suggestion(_type, nil), do: nil
  def next_due_suggestion(%Type{recurring_interval: "none"}, _due_by), do: nil
  def next_due_suggestion(%Type{recurring_interval: "custom"}, _due_by), do: nil

  def next_due_suggestion(%Type{recurring_interval: interval}, due_by) do
    case interval do
      "weekly" -> Date.add(due_by, 7)
      "every_two_weeks" -> Date.add(due_by, 14)
      "monthly" -> shift_month(due_by, 1)
      "quarterly" -> shift_month(due_by, 3)
      "semiannual" -> shift_month(due_by, 6)
      "annual" -> shift_month(due_by, 12)
      _ -> nil
    end
  end

  def shift_month(%Date{} = date, months) when is_integer(months) do
    total_months = date.year * 12 + date.month - 1 + months
    year = div(total_months, 12)
    month = rem(total_months, 12) + 1
    last_day = Date.days_in_month(%Date{year: year, month: month, day: 1})
    day = min(date.day, last_day)
    %Date{year: year, month: month, day: day}
  end
end
