defmodule ArgusWeb.ObligationLive.IndexHelpers do
  @moduledoc false

  alias Argus.Accounts.Scope
  alias Argus.Obligations
  alias Argus.Obligations.{Obligation, Urgency}

  @lifecycles ~w(live completed skipped all)a
  @page_size 25
  @urgency_window_days 365
  @urgency_rank %{overdue: 0, due_soon: 1, ok: 2}

  @doc "Lifecycle options for the status dropdown, as `{value, label}` pairs."
  def lifecycles, do: Enum.map(@lifecycles, &{Atom.to_string(&1), lifecycle_label(&1)})

  @doc "Whether the list defaults to the current user's own work."
  def default_mine?(%Scope{role: :member}), do: true
  def default_mine?(_scope), do: false

  def parse_lifecycle("completed"), do: :completed
  def parse_lifecycle("skipped"), do: :skipped
  def parse_lifecycle("all"), do: :all
  def parse_lifecycle(_), do: :live

  def lifecycle_label(:live), do: "Live"
  def lifecycle_label(:completed), do: "Completed"
  def lifecycle_label(:skipped), do: "Skipped"
  def lifecycle_label(:all), do: "All"

  @doc "Combined status atom for `Obligations.list_obligations/2`."
  def status_atom(true, :live), do: :my_live
  def status_atom(true, :completed), do: :my_completed
  def status_atom(true, :skipped), do: :my_skipped
  def status_atom(true, :all), do: :my_all
  def status_atom(false, lifecycle), do: lifecycle

  def empty_message(mine?, lifecycle) do
    who = if mine?, do: " assigned to you", else: ""

    case lifecycle do
      :live -> "No live duties#{who}."
      :completed -> "No completed duties#{who}."
      :skipped -> "No skipped duties#{who}."
      :all -> "No duties#{who}."
    end
  end

  @doc """
  Sort options for the dropdown. `Someday` floats no-due-date duties to the top;
  `Most urgent` is offered only on the live lifecycle.
  """
  def sorts(:live),
    do: [
      {"due_asc", "Due soonest"},
      {"due_desc", "Due latest"},
      {"urgency", "Most urgent"},
      {"someday", "Someday"},
      {"title", "Title A–Z"}
    ]

  def sorts(_lifecycle),
    do: [
      {"due_asc", "Due soonest"},
      {"due_desc", "Due latest"},
      {"someday", "Someday"},
      {"title", "Title A–Z"}
    ]

  def effective_sort(sort, lifecycle) do
    allowed = Enum.map(sorts(lifecycle), fn {v, _} -> parse_sort(v) end)
    if sort in allowed, do: sort, else: :due_asc
  end

  def parse_sort("due_desc"), do: :due_desc
  def parse_sort("title"), do: :title
  def parse_sort("urgency"), do: :urgency
  def parse_sort("someday"), do: :someday
  def parse_sort(_), do: :due_asc

  def load_rows(scope, today, mine?, lifecycle, query) do
    status = status_atom(mine?, lifecycle)

    case Obligations.list_obligations(scope, status: status, query: query) do
      :not_authorise -> []
      obligations -> build_rows(obligations, today)
    end
  end

  def load_page(scope, today, mine?, lifecycle, query, sort, cursor) do
    status = status_atom(mine?, lifecycle)
    do_load_page(scope, today, status, query, effective_sort(sort, lifecycle), cursor)
  end

  defp do_load_page(scope, today, status, query, sort, cursor) when sort != :urgency do
    case Obligations.list_obligations_page(scope,
           status: status,
           query: query,
           sort: sort,
           cursor: cursor,
           limit: @page_size
         ) do
      :not_authorise ->
        %{rows: [], cursor: nil, end?: true}

      page ->
        %{rows: build_rows(page.rows, today), cursor: page.cursor, end?: page.end?}
    end
  end

  # urgency reaches here only for the live lifecycle (effective_sort guarantees it).
  # The list may now contain dateless duties; they are appended after the dated
  # tail (see serve_tail's due_after_or_null) so they never silently drop.
  defp do_load_page(scope, today, status, query, :urgency, cursor) do
    window_end = Date.add(today, @urgency_window_days)

    case decode_urgency_cursor(cursor) do
      {:window, offset} -> serve_window(scope, today, status, window_end, query, offset)
      {:tail, inner} -> serve_tail(scope, today, status, window_end, query, inner)
    end
  end

  # In-memory urgency ranking over the dated rows due within the window
  # (`due_before` excludes nulls, so dateless rows never enter the window).
  defp serve_window(scope, today, status, window_end, query, offset) do
    ranked =
      case Obligations.list_obligations_page(
             scope,
             status: status,
             query: query,
             sort: :due_asc,
             due_before: window_end,
             limit: :all
           ) do
        :not_authorise -> []
        page -> Map.fetch!(page, :rows)
      end
      |> Enum.sort_by(fn %Obligation{} = o ->
        {@urgency_rank[Urgency.classify(o.obligation_type, o.due_by, today)],
         Date.to_iso8601(o.due_by)}
      end)

    page = ranked |> Enum.slice(offset, @page_size) |> build_rows(today)
    next_offset = offset + @page_size

    if next_offset < length(ranked) do
      %{rows: page, cursor: encode_urgency_cursor({:window, next_offset}), end?: false}
    else
      %{rows: page, cursor: encode_urgency_cursor({:tail, nil}), end?: false}
    end
  end

  # The tail is the rest, SQL-keyset by `due_by` ascending NULLS LAST: dated rows
  # beyond the window first, then dateless duties (urgency :none) at the very end.
  defp serve_tail(scope, today, status, window_end, query, inner_cursor) do
    case Obligations.list_obligations_page(scope,
           status: status,
           query: query,
           sort: :due_asc,
           due_after_or_null: window_end,
           cursor: inner_cursor
         ) do
      :not_authorise ->
        %{rows: [], cursor: nil, end?: true}

      page ->
        cursor = if page.end?, do: nil, else: encode_urgency_cursor({:tail, page.cursor})
        %{rows: build_rows(page.rows, today), cursor: cursor, end?: page.end?}
    end
  end

  defp decode_urgency_cursor(nil), do: {:window, 0}

  defp decode_urgency_cursor(cursor) when is_binary(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, decoded} <- Jason.decode(json) do
      case decoded do
        %{"m" => "w", "o" => offset} -> {:window, offset}
        %{"m" => "t", "c" => inner} -> {:tail, inner}
        _ -> {:window, 0}
      end
    else
      _ -> {:window, 0}
    end
  end

  defp encode_urgency_cursor({:window, offset}),
    do: %{"m" => "w", "o" => offset} |> Jason.encode!() |> Base.url_encode64(padding: false)

  defp encode_urgency_cursor({:tail, inner}),
    do: %{"m" => "t", "c" => inner} |> Jason.encode!() |> Base.url_encode64(padding: false)

  defp build_rows(obligations, today) do
    summaries = Obligations.event_summaries_for(obligations)

    Enum.map(obligations, fn obligation ->
      %{event_count: event_count, latest_event: latest_event} =
        Map.fetch!(summaries, obligation.id)

      %{
        obligation: obligation,
        cycle_status: cycle_status(obligation),
        urgency: Urgency.classify(obligation.obligation_type, obligation.due_by, today),
        tier: Urgency.tier(obligation.obligation_type, obligation.due_by, today),
        event_count: event_count,
        latest_event: latest_event
      }
    end)
  end

  def cycle_status(%Obligation{completed_at: %DateTime{}}), do: :completed
  # End-series stamps BOTH closed_at and series_ended_at. A completed-in-error
  # replacement carries series_ended_at (to block spawning) but is still live, so
  # series_ended must be gated on the cycle actually being closed.
  def cycle_status(%Obligation{closed_at: %DateTime{}, series_ended_at: %DateTime{}}),
    do: :series_ended

  def cycle_status(%Obligation{closed_at: %DateTime{}}), do: :skipped
  def cycle_status(_), do: :live
end
