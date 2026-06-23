defmodule ArgusWeb.ObligationLive.IndexHelpers do
  @moduledoc false

  alias Argus.Accounts.Scope
  alias Argus.Obligations
  alias Argus.Obligations.{Obligation, Urgency}

  @lifecycles ~w(live someday completed skipped all)a
  @page_size 25
  @urgency_window_days 365
  @urgency_rank %{overdue: 0, due_soon: 1, ok: 2}

  @doc "Lifecycle options for the status dropdown, as `{value, label}` pairs."
  def lifecycles, do: Enum.map(@lifecycles, &{Atom.to_string(&1), lifecycle_label(&1)})

  @doc "Whether the list defaults to the current user's own work."
  def default_mine?(%Scope{role: :member}), do: true
  def default_mine?(_scope), do: false

  def parse_lifecycle("someday"), do: :someday
  def parse_lifecycle("completed"), do: :completed
  def parse_lifecycle("skipped"), do: :skipped
  def parse_lifecycle("all"), do: :all
  def parse_lifecycle(_), do: :live

  def lifecycle_label(:live), do: "Live"
  def lifecycle_label(:someday), do: "Someday"
  def lifecycle_label(:completed), do: "Completed"
  def lifecycle_label(:skipped), do: "Skipped"
  def lifecycle_label(:all), do: "All"

  @doc "Combined status atom for `Obligations.list_obligations/2`."
  def status_atom(true, :live), do: :my_live
  def status_atom(true, :someday), do: :my_someday
  def status_atom(true, :completed), do: :my_completed
  def status_atom(true, :skipped), do: :my_skipped
  def status_atom(true, :all), do: :my_all
  def status_atom(false, lifecycle), do: lifecycle

  def empty_message(mine?, :someday) do
    who = if mine?, do: " assigned to you", else: ""
    "No someday duties#{who}."
  end

  def empty_message(mine?, lifecycle) do
    who = if mine?, do: " assigned to you", else: ""

    case lifecycle do
      :live -> "No live duties#{who}."
      :completed -> "No completed duties#{who}."
      :skipped -> "No skipped duties#{who}."
      :all -> "No duties#{who}."
    end
  end

  @doc "Sort options for the dropdown; urgency is offered only on the live lifecycle."
  def sorts(:live),
    do: [
      {"due_asc", "Due soonest"},
      {"due_desc", "Due latest"},
      {"urgency", "Most urgent"},
      {"title", "Title A–Z"}
    ]

  def sorts(:someday),
    do: [{"recent", "Recently added"}, {"title", "Title A–Z"}]

  def sorts(_lifecycle),
    do: [{"due_asc", "Due soonest"}, {"due_desc", "Due latest"}, {"title", "Title A–Z"}]

  def parse_sort("due_desc"), do: :due_desc
  def parse_sort("title"), do: :title
  def parse_sort("urgency"), do: :urgency
  def parse_sort("recent"), do: :recent
  def parse_sort(_), do: :due_asc

  def effective_sort(sort, lifecycle) do
    allowed = Enum.map(sorts(lifecycle), fn {v, _} -> parse_sort(v) end)
    if sort in allowed, do: sort, else: default_sort(lifecycle)
  end

  defp default_sort(:someday), do: :recent
  defp default_sort(_), do: :due_asc

  def load_rows(scope, today, mine?, lifecycle, query) do
    status = status_atom(mine?, lifecycle)

    scope
    |> Obligations.list_obligations(status: status, query: query)
    |> build_rows(today)
  end

  def load_page(scope, today, mine?, lifecycle, query, sort, cursor) do
    status = status_atom(mine?, lifecycle)
    do_load_page(scope, today, status, lifecycle, query, effective_sort(sort, lifecycle), cursor)
  end

  # Non-urgency (and non-live urgency, already downgraded): straight SQL paging.
  defp do_load_page(scope, today, status, _lifecycle, query, sort, cursor)
       when sort != :urgency do
    page =
      Obligations.list_obligations_page(scope,
        status: status,
        query: query,
        sort: sort,
        cursor: cursor,
        limit: @page_size
      )

    %{rows: build_rows(page.rows, today), cursor: page.cursor, end?: page.end?}
  end

  defp do_load_page(scope, today, status, :live, query, :urgency, cursor) do
    window_end = Date.add(today, @urgency_window_days)

    case decode_urgency_cursor(cursor) do
      {:window, offset} -> serve_window(scope, today, status, query, window_end, offset)
      {:tail, inner} -> serve_tail(scope, today, status, query, window_end, inner)
    end
  end

  defp serve_window(scope, today, status, query, window_end, offset) do
    # Rank the bare obligations by urgency — this needs only the (preloaded) type
    # and due_by, not event summaries — so we avoid summarising the whole window on
    # every load_more and only build full rows (with summaries) for the sliced page.
    ranked =
      scope
      |> Obligations.list_obligations_page(
        status: status,
        query: query,
        sort: :due_asc,
        due_before: window_end,
        limit: :all
      )
      |> Map.fetch!(:rows)
      |> Enum.sort_by(fn %Obligation{} = o ->
        {@urgency_rank[Urgency.classify(o.obligation_type, o.due_by, today)],
         Date.to_iso8601(o.due_by)}
      end)

    page = ranked |> Enum.slice(offset, @page_size) |> build_rows(today)
    next_offset = offset + @page_size

    if next_offset < length(ranked) do
      %{rows: page, cursor: encode_urgency_cursor({:window, next_offset}), end?: false}
    else
      # Window exhausted; hand off to the > window_end tail (may be empty).
      %{rows: page, cursor: encode_urgency_cursor({:tail, nil}), end?: false}
    end
  end

  defp serve_tail(scope, today, status, query, window_end, inner_cursor) do
    page =
      Obligations.list_obligations_page(scope,
        status: status,
        query: query,
        sort: :due_asc,
        due_after: window_end,
        cursor: inner_cursor
      )

    cursor = if page.end?, do: nil, else: encode_urgency_cursor({:tail, page.cursor})
    %{rows: build_rows(page.rows, today), cursor: cursor, end?: page.end?}
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
  def cycle_status(%Obligation{series_ended_at: %DateTime{}}), do: :series_ended
  def cycle_status(%Obligation{closed_at: %DateTime{}}), do: :skipped
  def cycle_status(_), do: :live
end
