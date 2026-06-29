defmodule Tugas.Duties do
  @moduledoc """
  Duties domain — cycles, events, and workflow.
  """

  import Ecto.Query, warn: false

  alias Tugas.Accounts.{Scope, User}
  alias Tugas.Authorization
  alias Tugas.Entities.Membership

  alias Tugas.Duties.{
    AuditLog,
    Collaborator,
    Completion,
    Event,
    EventDocument,
    Duty,
    Pagination,
    Recurrence,
    Series,
    Type
  }

  alias Tugas.Repo
  alias Tugas.Uploads

  def live(query \\ Duty) do
    from(o in query, where: is_nil(o.completed_at) and is_nil(o.closed_at))
  end

  def list_my_work(scope), do: list_duties(scope, status: :my_live)

  def list_types(%Scope{entity: %_{} = entity}) do
    Type
    |> where([t], t.entity_id == ^entity.id)
    |> order_by([t], asc: t.name)
    |> Repo.all()
  end

  def list_types(_), do: :not_authorise

  def get_type!(%Scope{entity: %_{} = entity}, id) do
    Type
    |> where([t], t.id == ^id and t.entity_id == ^entity.id)
    |> Repo.one!()
  end

  def get_type!(_scope, _id), do: raise(Ecto.NoResultsError, queryable: Type)

  def change_type(%Type{} = type, attrs \\ %{}), do: Type.changeset(type, attrs)

  def create_type(%Scope{entity: %_{} = entity} = scope, attrs) do
    if Authorization.can?(scope, :manage_types) do
      %Type{entity_id: entity.id}
      |> Type.changeset(attrs)
      |> Repo.insert()
    else
      :not_authorise
    end
  end

  def create_type(_scope, _attrs), do: :not_authorise

  def update_type(%Scope{entity: %_{} = entity} = scope, %Type{} = type, attrs) do
    if Authorization.can?(scope, :manage_types) and type.entity_id == entity.id do
      changeset = Type.changeset(type, attrs)

      cond do
        not changeset.valid? ->
          {:error, changeset}

        changeset.changes == %{} ->
          {:ok, type}

        true ->
          old_complete_documents = type.complete_documents

          Ecto.Multi.new()
          |> Ecto.Multi.update(:type, changeset)
          |> Ecto.Multi.run(:propagate, fn repo, %{type: updated} ->
            if normalize_slot_csv(old_complete_documents) !=
                 normalize_slot_csv(updated.complete_documents) do
              propagate_complete_documents_to_live(repo, scope, updated)
            else
              {:ok, 0}
            end
          end)
          |> Repo.transaction()
          |> case do
            {:ok, %{type: updated}} -> {:ok, updated}
            {:error, :type, changeset, _} -> {:error, changeset}
            {:error, _, reason, _} -> {:error, reason}
          end
      end
    else
      :not_authorise
    end
  end

  def update_type(_scope, _type, _attrs), do: :not_authorise

  def get_duty!(%Scope{entity: %_{} = entity}, id) do
    Duty
    |> where([o], o.id == ^id and o.entity_id == ^entity.id)
    |> preload([
      :duty_type,
      :primary_assignee,
      [collaborators: :user],
      [events: [:documents, :status_by]]
    ])
    |> Repo.one!()
  end

  def get_duty!(_scope, _id), do: raise(Ecto.NoResultsError, queryable: Duty)

  def change_duty(%Duty{} = duty, attrs \\ %{}) do
    Duty.changeset(duty, attrs)
  end

  def list_team_overview(scope), do: list_duties(scope, status: :live)

  def list_unassigned(%Scope{entity: %_{} = entity}) do
    Duty
    |> where([o], o.entity_id == ^entity.id)
    |> live()
    |> where([o], is_nil(o.primary_assignee_id))
    |> order_by([o], asc: o.due_by)
    |> preload([:duty_type, :primary_assignee])
    |> Repo.all()
  end

  def list_unassigned(_), do: :not_authorise

  @recently_completed_days 14

  def list_recently_completed(scope, days \\ @recently_completed_days)

  def list_recently_completed(%Scope{entity: %_{} = entity}, days) do
    cutoff = DateTime.utc_now(:second) |> DateTime.add(-days * 24 * 3600, :second)

    Duty
    |> where([o], o.entity_id == ^entity.id)
    |> where([o], not is_nil(o.completed_at) and o.completed_at >= ^cutoff)
    |> order_by([o], desc: o.completed_at)
    |> preload([:duty_type, :primary_assignee])
    |> Repo.all()
  end

  def list_recently_completed(_, _), do: :not_authorise

  @status_filters ~w(my_live my_completed my_skipped my_all live completed skipped all)a

  @doc """
  Lists duties for the entity scope.

  Options:
    * `:status` — `:my_live`, `:my_completed`, `:live` (default), `:completed`,
      `:skipped`, or `:all`. My filters scope to primary assignee or collaborator.
    * `:query` — optional case-insensitive search on title, type name, assignee email
  """
  def list_duties(scope, opts \\ [])

  def list_duties(%Scope{entity: %_{} = entity, user: %_{} = user}, opts) do
    status = Keyword.get(opts, :status, :live)
    query = Keyword.get(opts, :query)

    unless status in @status_filters do
      raise ArgumentError, "invalid status filter #{inspect(status)}"
    end

    Duty
    |> where([o], o.entity_id == ^entity.id)
    |> scope_to_assignee(status, user)
    |> apply_status_filter(status)
    |> apply_due_bound(:before, Keyword.get(opts, :due_before))
    |> apply_due_bound(:after, Keyword.get(opts, :due_after))
    |> apply_dateless_filter(Keyword.get(opts, :dateless))
    |> apply_list_order(status)
    |> preload([:duty_type, :primary_assignee])
    |> Repo.all()
    |> filter_by_query(query)
  end

  def list_duties(_, _), do: :not_authorise

  defp scope_to_assignee(query, status, user)
       when status in [:my_live, :my_completed, :my_skipped, :my_all] do
    collaborator_ids = collaborator_duty_ids(user.id)

    where(
      query,
      [o],
      o.primary_assignee_id == ^user.id or o.id in subquery(collaborator_ids)
    )
  end

  defp scope_to_assignee(query, _status, _user), do: query

  defp apply_status_filter(query, status) when status in [:live, :my_live], do: live(query)

  defp apply_status_filter(query, status) when status in [:completed, :my_completed] do
    from o in query, where: not is_nil(o.completed_at)
  end

  defp apply_status_filter(query, status) when status in [:skipped, :my_skipped] do
    from o in query, where: not is_nil(o.closed_at)
  end

  defp apply_status_filter(query, status) when status in [:all, :my_all], do: query

  defp apply_list_order(query, status) when status in [:live, :my_live],
    do: order_by(query, [o], asc: o.due_by)

  defp apply_list_order(query, status) when status in [:completed, :my_completed],
    do: order_by(query, [o], desc: o.completed_at)

  defp apply_list_order(query, status) when status in [:skipped, :my_skipped],
    do: order_by(query, [o], desc: o.closed_at)

  defp apply_list_order(query, _), do: order_by(query, [o], desc: o.due_by)

  defp filter_by_query(duties, query) when query in [nil, ""], do: duties

  defp filter_by_query(duties, query) do
    q = String.downcase(query)

    Enum.filter(duties, fn duty ->
      String.contains?(String.downcase(duty.title), q) or
        String.contains?(String.downcase(duty.duty_type.name), q) or
        assignee_matches_query?(duty, q)
    end)
  end

  defp assignee_matches_query?(%Duty{primary_assignee: nil}, q),
    do: String.contains?("unassigned", q)

  defp assignee_matches_query?(%Duty{primary_assignee: assignee}, q),
    do: String.contains?(String.downcase(assignee.email), q)

  defp collaborator_duty_ids(user_id) do
    from c in Collaborator, where: c.user_id == ^user_id, select: c.duty_id
  end

  @page_size 25

  def list_duties_page(scope, opts \\ [])

  def list_duties_page(%Scope{entity: %_{} = entity, user: %_{} = user}, opts) do
    status = Keyword.get(opts, :status, :live)
    sort = normalize_page_sort(Keyword.get(opts, :sort, :due_asc))
    cursor = Pagination.decode(Keyword.get(opts, :cursor))
    limit = Keyword.get(opts, :limit, @page_size)

    unless status in @status_filters do
      raise ArgumentError, "invalid status filter #{inspect(status)}"
    end

    query =
      Duty
      |> join(:left, [o], t in assoc(o, :duty_type), as: :type)
      |> join(:left, [o], a in assoc(o, :primary_assignee), as: :assignee)
      |> where([o], o.entity_id == ^entity.id)
      |> scope_to_assignee(status, user)
      |> apply_status_filter(status)
      |> apply_due_bound(:before, Keyword.get(opts, :due_before))
      |> apply_due_bound(:after, Keyword.get(opts, :due_after))
      |> apply_due_bound(:after_or_null, Keyword.get(opts, :due_after_or_null))
      |> apply_page_search(Keyword.get(opts, :query))
      |> apply_page_order(sort)
      |> apply_page_cursor(sort, cursor)
      |> preload([:duty_type, :primary_assignee])

    query
    |> maybe_limit(limit)
    |> Repo.all()
    |> paginate(sort, limit)
  end

  def list_duties_page(_, _), do: :not_authorise

  defp normalize_page_sort(sort) when sort in [:due_asc, :due_desc, :title, :recent, :someday],
    do: sort

  defp normalize_page_sort(_), do: :due_asc

  defp apply_due_bound(query, _which, nil), do: query
  defp apply_due_bound(query, :before, %Date{} = d), do: where(query, [o], o.due_by <= ^d)
  defp apply_due_bound(query, :after, %Date{} = d), do: where(query, [o], o.due_by > ^d)

  defp apply_due_bound(query, :after_or_null, %Date{} = d),
    do: where(query, [o], o.due_by > ^d or is_nil(o.due_by))

  defp apply_dateless_filter(query, true), do: where(query, [o], is_nil(o.due_by))
  defp apply_dateless_filter(query, _), do: query

  defp apply_page_search(query, q) when q in [nil, ""], do: query

  defp apply_page_search(query, q) do
    like = "%#{escape_like(q)}%"
    unassigned? = String.contains?("unassigned", String.downcase(q))

    from [o, type: t, assignee: a] in query,
      where:
        ilike(o.title, ^like) or ilike(t.name, ^like) or ilike(a.email, ^like) or
          (^unassigned? and is_nil(o.primary_assignee_id))
  end

  defp escape_like(q), do: String.replace(q, ["\\", "%", "_"], &("\\" <> &1))

  defp apply_page_order(query, :due_asc),
    do: order_by(query, [o], asc_nulls_last: o.due_by, asc: o.id)

  defp apply_page_order(query, :due_desc),
    do: order_by(query, [o], desc_nulls_last: o.due_by, asc: o.id)

  defp apply_page_order(query, :title),
    do: order_by(query, [o], asc: fragment("lower(?)", o.title), asc: o.id)

  defp apply_page_order(query, :recent), do: order_by(query, [o], desc: o.inserted_at, desc: o.id)

  # Someday sort: no-due-date duties first (NULLS FIRST), then the dated ones by due date.
  defp apply_page_order(query, :someday),
    do: order_by(query, [o], asc_nulls_first: o.due_by, asc: o.id)

  defp apply_page_cursor(query, _sort, nil), do: query

  @null_key " null"

  defp apply_page_cursor(query, :due_asc, %{key: @null_key, id: id}),
    do: where(query, [o], is_nil(o.due_by) and o.id > ^id)

  defp apply_page_cursor(query, :due_asc, %{key: k, id: id}) do
    case Date.from_iso8601(k) do
      {:ok, d} ->
        where(query, [o], o.due_by > ^d or (o.due_by == ^d and o.id > ^id) or is_nil(o.due_by))

      _ ->
        query
    end
  end

  defp apply_page_cursor(query, :due_desc, %{key: @null_key, id: id}),
    do: where(query, [o], is_nil(o.due_by) and o.id > ^id)

  defp apply_page_cursor(query, :due_desc, %{key: k, id: id}) do
    case Date.from_iso8601(k) do
      {:ok, d} ->
        where(query, [o], o.due_by < ^d or (o.due_by == ^d and o.id > ^id) or is_nil(o.due_by))

      _ ->
        query
    end
  end

  defp apply_page_cursor(query, :recent, %{key: k, id: id}) do
    case DateTime.from_iso8601(k) do
      {:ok, ts, _} ->
        where(query, [o], o.inserted_at < ^ts or (o.inserted_at == ^ts and o.id < ^id))

      _ ->
        query
    end
  end

  # Someday keyset: NULLS FIRST. After a null row, more nulls (then all dated);
  # after a dated row, the nulls are already behind us, so only later dated rows.
  defp apply_page_cursor(query, :someday, %{key: @null_key, id: id}),
    do: where(query, [o], (is_nil(o.due_by) and o.id > ^id) or not is_nil(o.due_by))

  defp apply_page_cursor(query, :someday, %{key: k, id: id}) do
    case Date.from_iso8601(k) do
      {:ok, d} ->
        where(
          query,
          [o],
          not is_nil(o.due_by) and (o.due_by > ^d or (o.due_by == ^d and o.id > ^id))
        )

      _ ->
        query
    end
  end

  defp apply_page_cursor(query, :title, %{key: k, id: id}) do
    where(
      query,
      [o],
      fragment("lower(?)", o.title) > ^k or
        (fragment("lower(?)", o.title) == ^k and o.id > ^id)
    )
  end

  defp maybe_limit(query, :all), do: query
  defp maybe_limit(query, limit), do: limit(query, ^(limit + 1))

  defp paginate(rows, _sort, :all), do: %{rows: rows, cursor: nil, end?: true}

  defp paginate(rows, sort, limit) do
    {page, rest} = Enum.split(rows, limit)
    has_more = rest != []

    cursor =
      if has_more do
        last = List.last(page)
        Pagination.encode(%{key: cursor_key(sort, last), id: last.id})
      end

    %{rows: page, cursor: cursor, end?: not has_more}
  end

  defp cursor_key(:title, %Duty{title: t}), do: String.downcase(t)
  defp cursor_key(:recent, %Duty{inserted_at: ts}), do: DateTime.to_iso8601(ts)
  defp cursor_key(_sort, %Duty{due_by: nil}), do: @null_key
  defp cursor_key(_sort, %Duty{due_by: d}), do: Date.to_iso8601(d)

  @doc """
  All cycles sharing a `series_id`, oldest first — the recurrence history.
  """
  def list_series(series_id) do
    Duty
    |> where([o], o.series_id == ^series_id)
    |> series_order()
    |> Repo.all()
  end

  @doc """
  The immediately adjacent cycles in a recurrence series.

  Ordering matches `list_series/1` (`due_by` ascending, nulls last, then
  `inserted_at`, then `id`). Returns `%{previous: duty | nil, next: duty | nil}`
  with minimal `Duty` structs (`id`, `due_by` only).
  """
  def series_neighbors(%Duty{series_id: series_id, entity_id: entity_id} = duty) do
    rows =
      Duty
      |> where([o], o.series_id == ^series_id and o.entity_id == ^entity_id)
      |> series_order()
      |> select([o], %{id: o.id, due_by: o.due_by})
      |> Repo.all()

    case Enum.find_index(rows, &(&1.id == duty.id)) do
      nil ->
        %{previous: nil, next: nil}

      idx ->
        %{
          previous: series_neighbor_at(rows, idx - 1),
          next: series_neighbor_at(rows, idx + 1)
        }
    end
  end

  defp series_order(query),
    do: order_by(query, [o], asc_nulls_last: o.due_by, asc: o.inserted_at, asc: o.id)

  defp series_neighbor_at(_rows, index) when index < 0, do: nil

  defp series_neighbor_at(rows, index) do
    case Enum.at(rows, index) do
      nil -> nil
      %{id: id, due_by: due_by} -> %Duty{id: id, due_by: due_by}
    end
  end

  def list_events(%Duty{} = duty) do
    Event
    |> where([e], e.duty_id == ^duty.id)
    |> order_by([e], asc: e.inserted_at)
    |> Repo.all()
  end

  def latest_event(%Duty{} = duty) do
    Event
    |> where([e], e.duty_id == ^duty.id)
    |> order_by([e],
      desc: e.inserted_at,
      desc:
        fragment(
          "CASE ? WHEN 'done' THEN 5 WHEN 'series_ended' THEN 4 WHEN 'skipped' THEN 3 WHEN 'in_progress' THEN 2 WHEN 'open' THEN 1 ELSE 0 END",
          e.status
        )
    )
    |> limit(1)
    |> Repo.one!()
  end

  @doc """
  Batch-fetches event count and latest event (with `status_by`) for a list of duties.
  Returns a map of `duty_id => %{event_count: integer, latest_event: Event | nil}`.
  """
  def event_summaries_for(duties) when is_list(duties) do
    duties
    |> Enum.map(& &1.id)
    |> event_summaries_for_ids()
  end

  def event_summaries_for_ids([]), do: %{}

  def event_summaries_for_ids(ids) do
    counts =
      Event
      |> where([e], e.duty_id in ^ids)
      |> group_by([e], e.duty_id)
      |> select([e], {e.duty_id, count(e.id)})
      |> Repo.all()
      |> Map.new()

    latest_events =
      Event
      |> where([e], e.duty_id in ^ids)
      |> order_by([e],
        asc: e.duty_id,
        desc: e.inserted_at,
        desc:
          fragment(
            "CASE ? WHEN 'done' THEN 5 WHEN 'series_ended' THEN 4 WHEN 'skipped' THEN 3 WHEN 'in_progress' THEN 2 WHEN 'open' THEN 1 ELSE 0 END",
            e.status
          )
      )
      |> distinct([e], e.duty_id)
      |> preload(:status_by)
      |> Repo.all()
      |> Map.new(&{&1.duty_id, &1})

    Map.new(ids, fn id ->
      {id, %{event_count: Map.get(counts, id, 0), latest_event: Map.get(latest_events, id)}}
    end)
  end

  def create_duty(%Scope{} = scope, attrs) do
    with true <- Authorization.can?(scope, :create_duty),
         {:ok, type} <- fetch_type_for_entity(scope, attrs),
         :ok <- validate_open_note(attrs),
         :ok <- validate_duty_assignees(scope, attrs),
         {:ok, duty} <- insert_duty(scope, attrs, type) do
      {:ok, duty}
    else
      false -> :not_authorise
      {:error, :invalid_assignee} = error -> error
      {:error, _} = error -> error
    end
  end

  def start_progress(%Scope{} = scope, %Duty{} = duty, attrs \\ %{}) do
    duty = Repo.preload(duty, :collaborators)
    note = Map.get(attrs, :note) || Map.get(attrs, "note")

    with :ok <- ensure_duty_entity(scope, duty),
         true <- Authorization.can?(scope, :start_progress, duty),
         :ok <- ensure_progressable(duty),
         :ok <- validate_action_note(note),
         {:ok, event} <- insert_progress_event(scope, duty, note) do
      {:ok, event}
    else
      :not_found -> :not_found
      false -> :not_authorise
      {:error, _} = error -> error
    end
  end

  def list_cycle_documents(%Duty{} = duty) do
    EventDocument
    |> join(:inner, [d], e in Event, on: d.duty_event_id == e.id)
    |> where([d, e], e.duty_id == ^duty.id)
    |> Repo.all()
  end

  def get_document!(id) do
    Repo.get!(EventDocument, id)
  end

  def add_document(
        %Scope{} = scope,
        %Duty{} = duty,
        %Event{} = event,
        upload,
        document_slot
      ) do
    duty = Repo.preload(duty, :collaborators)

    with :ok <- ensure_duty_entity(scope, duty),
         true <- can_add_document?(scope, duty),
         :ok <- ensure_event_workable(event, duty),
         :ok <- validate_document_slot(duty, document_slot),
         {:ok, file} <- store_upload(upload, duty) do
      case insert_document(scope, event, file, document_slot) do
        {:ok, document} ->
          {:ok, document}

        {:error, _} = error ->
          Uploads.delete(%{file: file})
          error
      end
    else
      :not_found -> :not_found
      false -> :not_authorise
      {:error, _} = error -> error
    end
  end

  def list_audit_logs(%Duty{} = duty) do
    AuditLog
    |> where([l], l.duty_id == ^duty.id)
    |> order_by([l], desc: l.inserted_at, desc: l.id)
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Counts the *live* duties `user_id` is attached to in the scope's
  entity: cycles they primarily own and cycles they collaborate on. Used to
  warn an admin before disabling a member (the assignments that will be
  cleared). Returns `%{primary: n, collaborations: m}`.
  """
  def count_member_assignments(%Scope{entity: %{id: entity_id}}, user_id) do
    primary =
      Duty
      |> where([o], o.entity_id == ^entity_id and o.primary_assignee_id == ^user_id)
      |> live()
      |> Repo.aggregate(:count)

    collaborations =
      Duty
      |> join(:inner, [o], c in Collaborator, on: c.duty_id == o.id)
      |> where([o, c], o.entity_id == ^entity_id and c.user_id == ^user_id)
      |> live()
      |> Repo.aggregate(:count)

    %{primary: primary, collaborations: collaborations}
  end

  @doc """
  Batch variant of `count_member_assignments/2` for a whole entity: returns a
  map `%{user_id => %{primary: n, collaborations: m}}` over *live* duties,
  for the members-administration list. Users with no live assignments are
  absent from the map.
  """
  def member_assignment_counts(%{id: entity_id}) do
    primary =
      Duty
      |> where([o], o.entity_id == ^entity_id and not is_nil(o.primary_assignee_id))
      |> live()
      |> group_by([o], o.primary_assignee_id)
      |> select([o], {o.primary_assignee_id, count(o.id)})
      |> Repo.all()
      |> Map.new()

    collaborations =
      Duty
      |> join(:inner, [o], c in Collaborator, on: c.duty_id == o.id)
      |> where([o, c], o.entity_id == ^entity_id)
      |> live()
      |> group_by([o, c], c.user_id)
      |> select([o, c], {c.user_id, count(o.id)})
      |> Repo.all()
      |> Map.new()

    (Map.keys(primary) ++ Map.keys(collaborations))
    |> Enum.uniq()
    |> Map.new(fn uid ->
      {uid, %{primary: Map.get(primary, uid, 0), collaborations: Map.get(collaborations, uid, 0)}}
    end)
  end

  @doc """
  Detaches `user_id` from every *live* duty in the scope's entity:
  nulls `primary_assignee_id` (writing a `"primary_assignee"` audit row by the
  acting admin) on cycles they lead, and deletes their collaborator rows.
  Runs against `Repo`, so call it inside the disabling transaction. Returns
  `%{primary: n, collaborations: m}`.
  """
  def purge_member_assignments(%Scope{entity: %{id: entity_id}} = scope, user_id) do
    primary =
      Duty
      |> where([o], o.entity_id == ^entity_id and o.primary_assignee_id == ^user_id)
      |> live()
      |> Repo.all()

    Enum.each(primary, fn duty ->
      {:ok, updated} =
        duty
        |> Duty.changeset(%{primary_assignee_id: nil})
        |> Repo.update()

      insert_audit_log!(Repo, scope, updated, "primary_assignee", assignee_label(user_id), nil)
    end)

    collab_ids =
      Duty
      |> join(:inner, [o], c in Collaborator, on: c.duty_id == o.id)
      |> where([o, c], o.entity_id == ^entity_id and c.user_id == ^user_id)
      |> live()
      |> select([o], o.id)
      |> Repo.all()

    {collaborations, _} =
      Collaborator
      |> where([c], c.user_id == ^user_id and c.duty_id in ^collab_ids)
      |> Repo.delete_all()

    %{primary: length(primary), collaborations: collaborations}
  end

  def update_duty(%Scope{} = scope, %Duty{} = duty, attrs) do
    with :ok <- ensure_duty_entity(scope, duty),
         true <- Authorization.can?(scope, :edit_duty),
         true <- live_cycle?(duty) do
      changeset = Duty.changeset(duty, attrs)

      cond do
        not changeset.valid? ->
          {:error, changeset}

        changeset.changes == %{} ->
          {:ok, duty}

        true ->
          case validate_assignee_change(scope, changeset) do
            :ok -> apply_duty_update(scope, duty, changeset)
            {:error, :invalid_assignee} = error -> error
          end
      end
    else
      :not_found -> :not_found
      false -> :not_authorise
    end
  end

  def update_collaborators(%Scope{} = scope, %Duty{} = duty, user_ids) do
    with :ok <- ensure_duty_entity(scope, duty),
         true <- Authorization.can?(scope, :edit_duty),
         true <- live_cycle?(duty),
         :ok <- validate_entity_members(scope, user_ids) do
      current =
        Collaborator
        |> where([c], c.duty_id == ^duty.id)
        |> Repo.all()

      current_ids = MapSet.new(current, & &1.user_id)
      new_ids = MapSet.new(user_ids)
      to_add = MapSet.difference(new_ids, current_ids) |> MapSet.to_list()
      to_remove = MapSet.difference(current_ids, new_ids) |> MapSet.to_list()

      Ecto.Multi.new()
      |> Ecto.Multi.run(:audit, fn repo, _ ->
        Enum.each(to_add, fn user_id ->
          insert_audit_log!(
            repo,
            scope,
            duty,
            "collaborators",
            nil,
            assignee_label(user_id)
          )
        end)

        Enum.each(to_remove, fn user_id ->
          insert_audit_log!(
            repo,
            scope,
            duty,
            "collaborators",
            assignee_label(user_id),
            nil
          )
        end)

        {:ok, :logged}
      end)
      |> Ecto.Multi.insert_all(:added, Collaborator, fn _ ->
        now = DateTime.utc_now(:second)

        Enum.map(to_add, fn user_id ->
          %{
            id: Ecto.UUID.generate(),
            duty_id: duty.id,
            user_id: user_id,
            inserted_at: now
          }
        end)
      end)
      |> Ecto.Multi.delete_all(:removed, fn _ ->
        from c in Collaborator,
          where: c.duty_id == ^duty.id and c.user_id in ^to_remove
      end)
      |> Repo.transaction()
      |> case do
        {:ok, _} -> {:ok, Repo.preload(duty, :collaborators, force: true)}
        {:error, _, reason, _} -> {:error, reason}
      end
    else
      :not_found -> :not_found
      false -> :not_authorise
      {:error, :invalid_assignee} = error -> error
    end
  end

  @doc """
  True when `scope` may correct `event.note` on a live cycle (author within 48h, or manager/admin).
  """
  def note_editable?(%Scope{} = scope, %Event{} = event, %Duty{} = duty) do
    can_edit_note?(scope, event, duty)
  end

  @doc """
  True when `scope` may hard-delete a non-voided document within 48 hours on a live cycle.
  """
  def document_deletable?(
        %Scope{} = scope,
        %Duty{} = duty,
        %EventDocument{} = document
      ) do
    is_nil(document.voided_at) and
      live_cycle?(duty) and
      within_document_window?(document) and
      can_void_document?(scope, duty, document)
  end

  @doc """
  True when `scope` may void a non-voided document on this duty cycle.
  """
  def document_voidable?(
        %Scope{} = scope,
        %Duty{} = duty,
        %EventDocument{} = document
      ) do
    is_nil(document.voided_at) and can_void_document?(scope, duty, document) and
      (locked_cycle?(duty) or not within_document_window?(document))
  end

  @doc """
  True when voiding a document on this cycle requires a reason (admin on a locked cycle).
  """
  def document_void_reason_required?(%Duty{} = duty) do
    locked_cycle?(duty)
  end

  def edit_note(%Scope{} = scope, %Event{} = event, attrs) do
    duty = Repo.get!(Duty, event.duty_id)
    note = Map.get(attrs, :note) || Map.get(attrs, "note")

    with :ok <- ensure_duty_entity(scope, duty),
         true <- can_edit_note?(scope, event, duty) do
      old_note = event.note

      Ecto.Multi.new()
      |> Ecto.Multi.update(:event, Event.changeset(event, %{note: note}))
      |> Ecto.Multi.run(:audit, fn repo, %{event: updated} ->
        if old_note != updated.note do
          insert_audit_log!(repo, scope, duty, "note", old_note, updated.note, updated)
        end

        {:ok, :logged}
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{event: event}} -> {:ok, event}
        {:error, :event, changeset, _} -> {:error, changeset}
      end
    else
      :not_found -> :not_found
      false -> {:error, :locked}
    end
  end

  def void_document(
        %Scope{} = scope,
        %Duty{} = duty,
        %EventDocument{} = document,
        attrs
      ) do
    reason = Map.get(attrs, :reason) || Map.get(attrs, "reason")

    with :ok <- ensure_duty_entity(scope, duty),
         true <- document_voidable?(scope, duty, document),
         :ok <- validate_void_reason(duty, reason),
         {:ok, voided} <- void_document_row(scope, document, reason) do
      {:ok, voided}
    else
      :not_found -> :not_found
      false -> :not_authorise
      {:error, _} = error -> error
    end
  end

  def delete_document(
        %Scope{} = scope,
        %Duty{} = duty,
        %EventDocument{} = document
      ) do
    with :ok <- ensure_duty_entity(scope, duty),
         true <- document_deletable?(scope, duty, document),
         :ok <- ensure_document_on_cycle(duty, document),
         {:ok, deleted} <- delete_document_row(document) do
      {:ok, deleted}
    else
      :not_found -> :not_found
      false -> :not_authorise
      {:error, _} = error -> error
    end
  end

  def complete(%Scope{} = scope, %Duty{} = duty, attrs) do
    duty = Repo.preload(duty, [:collaborators, :duty_type])
    cycle_documents = list_cycle_documents(duty)

    with :ok <- ensure_duty_entity(scope, duty),
         true <- Authorization.can?(scope, :mark_done, duty),
         :ok <- Completion.validate_done_requirements(duty, attrs, cycle_documents),
         :ok <- validate_next_due(duty, attrs),
         {:ok, completed, spawned} <- complete_multi(scope, duty, attrs) do
      {:ok, completed, spawned}
    else
      :not_found -> :not_found
      false -> :not_authorise
      {:error, _} = error -> error
    end
  end

  @doc """
  Flags a *completed* cycle as completed-in-error and spawns a standalone one-off
  replacement (new `series_id`, `series_ended_at` set so it never spawns). Manager/admin
  only. The wrong cycle is never uncompleted; it is stamped + audited and linked to the
  replacement. Returns `{:ok, original, replacement}`.
  """
  def mark_completed_in_error(%Scope{} = scope, %Duty{} = duty, attrs) do
    duty = Repo.preload(duty, [:collaborators, :duty_type])
    reason = Map.get(attrs, :reason) || Map.get(attrs, "reason")

    replacement_due_by =
      case Map.get(attrs, :replacement_due_by) || Map.get(attrs, "replacement_due_by") do
        blank when blank in [nil, ""] -> duty.due_by
        provided -> provided
      end

    with :ok <- ensure_duty_entity(scope, duty),
         true <- Authorization.can?(scope, :mark_completed_in_error),
         :ok <- validate_correctable(duty),
         :ok <- validate_action_note(reason),
         {:ok, original, replacement} <-
           mark_in_error_multi(scope, duty, reason, replacement_due_by) do
      {:ok, original, replacement}
    else
      :not_found -> :not_found
      false -> :not_authorise
      {:error, _} = error -> error
    end
  end

  def skip(%Scope{} = scope, %Duty{} = duty, attrs) do
    duty = Repo.preload(duty, :duty_type)
    note = Map.get(attrs, :note) || Map.get(attrs, "note")
    next_due_by = Map.get(attrs, :next_due_by) || Map.get(attrs, "next_due_by")

    with :ok <- ensure_duty_entity(scope, duty),
         true <- Authorization.can?(scope, :skip),
         :ok <- validate_action_note(note),
         :ok <- validate_next_due(duty, attrs) do
      skip_multi(scope, duty, note, next_due_by)
    else
      :not_found -> :not_found
      false -> :not_authorise
      {:error, _} = error -> error
    end
  end

  defp skip_multi(scope, duty, note, next_due_by) do
    now = DateTime.utc_now(:second)
    spawn? = should_spawn_next?(duty, next_due_by)

    Ecto.Multi.new()
    |> Ecto.Multi.update_all(
      :close,
      live(Duty) |> where([o], o.id == ^duty.id),
      set: [closed_at: now, updated_at: now]
    )
    |> Ecto.Multi.run(:check, fn _repo, %{close: {count, _}} ->
      if count == 1, do: {:ok, :closed}, else: {:error, :not_live}
    end)
    |> Ecto.Multi.insert(:skipped_event, fn _ ->
      %Event{duty_id: duty.id, status_by_id: scope.user.id}
      |> Event.changeset(%{status: "skipped", note: note})
    end)
    |> maybe_spawn_next(spawn?, duty, next_due_by, scope.user.id)
    |> Repo.transaction()
    |> case do
      {:ok, %{spawn: spawned}} -> {:ok, Repo.get!(Duty, duty.id), spawned}
      {:ok, _} -> {:ok, Repo.get!(Duty, duty.id), nil}
      {:error, :check, :not_live, _} -> {:error, :not_live}
      {:error, :skipped_event, changeset, _} -> {:error, changeset}
      {:error, :spawn, reason, _} -> {:error, reason}
    end
  end

  defp maybe_spawn_next(multi, false, _duty, _next_due_by, _actor_id), do: multi

  defp maybe_spawn_next(multi, true, duty, next_due_by, actor_id) do
    Ecto.Multi.run(multi, :spawn, fn repo, _changes ->
      spawn_next_cycle(repo, duty, next_due_by, actor_id)
    end)
  end

  def end_series(%Scope{} = scope, %Duty{} = duty, attrs) do
    note = Map.get(attrs, :note) || Map.get(attrs, "note")

    with :ok <- ensure_duty_entity(scope, duty),
         true <- Authorization.can?(scope, :end_series),
         :ok <- validate_action_note(note) do
      now = DateTime.utc_now(:second)

      Ecto.Multi.new()
      |> Ecto.Multi.update_all(
        :duty,
        live(Duty) |> where([o], o.id == ^duty.id),
        set: [closed_at: now, series_ended_at: now, updated_at: now]
      )
      |> Ecto.Multi.run(:check, fn _repo, %{duty: {count, _}} ->
        if count == 1, do: {:ok, :updated}, else: {:error, :not_live}
      end)
      |> Ecto.Multi.insert(:series_ended_event, fn _ ->
        %Event{
          duty_id: duty.id,
          status_by_id: scope.user.id
        }
        |> Event.changeset(%{status: "series_ended", note: note})
      end)
      |> Repo.transaction()
      |> case do
        {:ok, _} ->
          {:ok, Repo.get!(Duty, duty.id)}

        {:error, :check, :not_live, _} ->
          {:error, :not_live}

        {:error, :series_ended_event, changeset, _} ->
          {:error, changeset}
      end
    else
      :not_found -> :not_found
      false -> :not_authorise
      {:error, _} = error -> error
    end
  end

  defp complete_multi(scope, duty, attrs) do
    now = DateTime.utc_now(:second)
    next_due_by = Map.get(attrs, :next_due_by) || Map.get(attrs, "next_due_by")
    note = Map.get(attrs, :note) || Map.get(attrs, "note")
    spawn? = should_spawn_next?(duty, next_due_by)

    Ecto.Multi.new()
    |> Ecto.Multi.update_all(
      :close,
      live(Duty) |> where([o], o.id == ^duty.id),
      set: [completed_at: now, updated_at: now]
    )
    |> Ecto.Multi.run(:check_live, fn _repo, %{close: {count, _}} ->
      if count == 1, do: {:ok, :closed}, else: {:error, :not_live}
    end)
    |> Ecto.Multi.insert(:done_event, fn _ ->
      %Event{
        duty_id: duty.id,
        status_by_id: scope.user.id
      }
      |> Event.changeset(%{status: "done", note: note})
    end)
    |> Ecto.Multi.run(:spawn, fn repo, %{close: {_, _}} ->
      if spawn? do
        case spawn_next_cycle(repo, duty, next_due_by, scope.user.id) do
          {:ok, new_duty} -> {:ok, new_duty}
          {:error, reason} -> {:error, reason}
        end
      else
        {:ok, nil}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{spawn: new_duty}} ->
        {:ok, Repo.get!(Duty, duty.id), new_duty}

      {:error, :check_live, :not_live, _} ->
        {:error, :not_live}

      {:error, :spawn, :not_live, _} ->
        {:error, :not_live}

      {:error, :done_event, changeset, _} ->
        {:error, changeset}
    end
  end

  defp should_spawn_next?(%Duty{} = duty, next_due_by) do
    not is_nil(duty.due_by) and Recurrence.recurring?(duty.duty_type) and
      not Series.ended?(duty.series_id) and not is_nil(next_due_by)
  end

  defp validate_next_due(%Duty{} = duty, attrs) do
    next_due_by = Map.get(attrs, :next_due_by) || Map.get(attrs, "next_due_by")
    type = duty.duty_type || Repo.get!(Type, duty.duty_type_id)

    if not is_nil(duty.due_by) and Recurrence.recurring?(type) and
         not Series.ended?(duty.series_id) and next_due_by in [nil, ""] do
      {:error, :next_due_required}
    else
      :ok
    end
  end

  defp spawn_next_cycle(repo, %Duty{} = done_duty, next_due_by, actor_id) do
    type = Repo.get!(Type, done_duty.duty_type_id)

    collaborators =
      Repo.all(from c in Collaborator, where: c.duty_id == ^done_duty.id)

    open_note =
      repo.one(
        from e in Event,
          where: e.duty_id == ^done_duty.id and e.status == "open",
          select: e.note
      ) || "Next cycle opened"

    now = DateTime.utc_now(:second)

    duty_changeset =
      %Duty{
        entity_id: done_duty.entity_id,
        series_id: done_duty.series_id,
        complete_documents: type.complete_documents
      }
      |> Duty.changeset(%{
        title: done_duty.title,
        duty_type_id: done_duty.duty_type_id,
        primary_assignee_id: done_duty.primary_assignee_id,
        due_by: next_due_by
      })

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:duty, duty_changeset)
    |> Ecto.Multi.insert_all(:collaborators, Collaborator, fn %{duty: duty} ->
      Enum.map(collaborators, fn c ->
        %{
          id: Ecto.UUID.generate(),
          duty_id: duty.id,
          user_id: c.user_id,
          inserted_at: now
        }
      end)
    end)
    |> Ecto.Multi.insert(:open_event, fn %{duty: duty} ->
      %Event{
        duty_id: duty.id,
        status_by_id: done_duty.primary_assignee_id || actor_id
      }
      |> Event.changeset(%{status: "open", note: open_note})
    end)
    |> repo.transaction()
    |> case do
      {:ok, %{duty: duty}} ->
        {:ok, duty}

      {:error, :duty, %Ecto.Changeset{errors: errors}, _} ->
        if constraint_error?(errors, :series_id),
          do: {:error, :not_live},
          else: {:error, :invalid}

      {:error, _, reason, _} ->
        {:error, reason}
    end
  end

  defp mark_in_error_multi(scope, duty, reason, replacement_due_by) do
    type = duty.duty_type
    now = DateTime.utc_now(:second)
    series_id = Ecto.UUID.generate()

    replacement_changeset =
      %Duty{
        entity_id: duty.entity_id,
        series_id: series_id,
        series_ended_at: now,
        complete_documents: type.complete_documents
      }
      |> Duty.changeset(%{
        title: duty.title,
        duty_type_id: duty.duty_type_id,
        primary_assignee_id: duty.primary_assignee_id,
        due_by: replacement_due_by
      })
      |> Ecto.Changeset.put_change(:replaces_id, duty.id)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:replacement, replacement_changeset)
    |> Ecto.Multi.insert_all(:collaborators, Collaborator, fn %{replacement: replacement} ->
      Enum.map(duty.collaborators, fn c ->
        %{
          id: Ecto.UUID.generate(),
          duty_id: replacement.id,
          user_id: c.user_id,
          inserted_at: now
        }
      end)
    end)
    |> Ecto.Multi.insert(:open_event, fn %{replacement: replacement} ->
      %Event{duty_id: replacement.id, status_by_id: scope.user.id}
      |> Event.changeset(%{status: "open", note: reason})
    end)
    |> Ecto.Multi.update(:original, fn %{replacement: replacement} ->
      duty
      |> Duty.changeset(%{})
      |> Ecto.Changeset.put_change(:completed_in_error_at, now)
      |> Ecto.Changeset.put_change(:completed_in_error_by_id, scope.user.id)
      |> Ecto.Changeset.put_change(:completed_in_error_reason, reason)
      |> Ecto.Changeset.put_change(:replaced_by_id, replacement.id)
    end)
    |> Ecto.Multi.run(:audit, fn repo, _changes ->
      insert_audit_log!(repo, scope, duty, "completed_in_error", nil, reason)
      {:ok, :logged}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{original: original, replacement: replacement}} ->
        {:ok, original, replacement}

      {:error, _step, %Ecto.Changeset{} = changeset, _} ->
        {:error, changeset}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  defp constraint_error?(errors, field) do
    Enum.any?(errors, fn
      {^field, {_msg, [constraint: :unique, constraint_name: _]}} -> true
      _ -> false
    end)
  end

  # A cycle accepts progress updates until it is closed. Multiple in_progress
  # events are allowed (each is a logged progress note); only terminal statuses
  # (done/cancelled/skipped/series_ended) close a cycle, so we reject once any
  # exists. `open` stays singular (created at creation) and `done` singular
  # (created at completion).
  defp ensure_progressable(%Duty{} = duty) do
    closed? =
      Event
      |> where([e], e.duty_id == ^duty.id and e.status in ^Event.terminal_statuses())
      |> Repo.exists?()

    if closed?, do: {:error, :not_live}, else: :ok
  end

  defp insert_progress_event(%Scope{user: user}, %Duty{} = duty, note) do
    %Event{
      duty_id: duty.id,
      status_by_id: user.id
    }
    |> Event.changeset(%{status: "in_progress", note: note})
    |> Repo.insert()
  end

  defp validate_open_note(attrs) do
    open_note = Map.get(attrs, :open_note) || Map.get(attrs, "open_note")
    validate_action_note(open_note)
  end

  defp fetch_type_for_entity(%Scope{entity: entity}, attrs) do
    type_id = Map.get(attrs, :duty_type_id) || Map.get(attrs, "duty_type_id")

    case Repo.get(Type, type_id) do
      %Type{entity_id: entity_id} = type when entity_id == entity.id -> {:ok, type}
      %Type{} -> {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  defp insert_duty(%Scope{user: user, entity: entity}, attrs, %Type{} = type) do
    series_id = Ecto.UUID.generate()
    open_note = Map.get(attrs, :open_note) || Map.get(attrs, "open_note")

    collaborator_ids =
      Map.get(attrs, :collaborator_ids, []) || Map.get(attrs, "collaborator_ids", [])

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:duty, fn _ ->
      %Duty{
        entity_id: entity.id,
        series_id: series_id,
        complete_documents: type.complete_documents
      }
      |> Duty.changeset(attrs)
    end)
    |> maybe_insert_collaborators(collaborator_ids)
    |> Ecto.Multi.insert(:open_event, fn %{duty: duty} ->
      %Event{
        duty_id: duty.id,
        status_by_id: user.id
      }
      |> Event.changeset(%{status: "open", note: open_note})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{duty: duty}} -> {:ok, duty}
      {:error, :duty, changeset, _} -> {:error, changeset}
      {:error, :open_event, changeset, _} -> {:error, changeset}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  defp apply_duty_update(scope, duty, changeset) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:duty, changeset)
    |> Ecto.Multi.run(:audit, fn repo, %{duty: updated} ->
      Enum.each(Map.drop(changeset.changes, [:someday]), fn {field, new_value} ->
        old_value = Map.get(duty, field)
        audit_field = audit_field_name(field)

        insert_audit_log!(
          repo,
          scope,
          updated,
          audit_field,
          audit_value(field, old_value),
          audit_value(field, new_value)
        )
      end)

      {:ok, :logged}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{duty: duty}} -> {:ok, duty}
      {:error, :duty, changeset, _} -> {:error, changeset}
    end
  end

  defp insert_audit_log!(repo, scope, duty, field, old_value, new_value, event \\ nil) do
    %AuditLog{
      duty_id: duty.id,
      duty_event_id: event && event.id,
      user_id: scope.user.id
    }
    |> AuditLog.changeset(%{field: field, old_value: old_value, new_value: new_value})
    |> repo.insert!()
  end

  defp audit_field_name(:primary_assignee_id), do: "primary_assignee"
  defp audit_field_name(field), do: Atom.to_string(field)

  defp audit_value(:primary_assignee_id, user_id), do: assignee_label(user_id)
  defp audit_value(:due_by, %Date{} = date), do: Date.to_iso8601(date)
  defp audit_value(_field, value) when is_nil(value), do: nil
  defp audit_value(_field, value), do: to_string(value)

  defp assignee_label(nil), do: nil

  defp assignee_label(user_id) do
    Repo.get!(User, user_id).email
  end

  defp can_edit_note?(scope, event, duty) do
    cond do
      locked_cycle?(duty) -> false
      Authorization.can?(scope, :edit_duty) -> true
      event.status_by_id == scope.user.id and within_note_window?(event) -> true
      true -> false
    end
  end

  defp within_note_window?(%Event{inserted_at: inserted_at}) do
    within_hours_window?(inserted_at)
  end

  defp within_document_window?(%EventDocument{inserted_at: inserted_at}) do
    within_hours_window?(inserted_at)
  end

  defp within_hours_window?(inserted_at) do
    DateTime.diff(DateTime.utc_now(:second), inserted_at, :second) <= 48 * 3600
  end

  defp insert_document(%Scope{user: user}, %Event{} = event, file, document_slot) do
    %EventDocument{
      duty_event_id: event.id,
      user_id: user.id
    }
    |> EventDocument.changeset(%{file: file, document_slot: document_slot})
    |> Repo.insert()
  end

  defp void_document_row(%Scope{user: user}, %EventDocument{} = document, reason) do
    document
    |> EventDocument.changeset(%{
      voided_at: DateTime.utc_now(:second),
      voided_by_id: user.id,
      void_reason: reason
    })
    |> Repo.update()
  end

  defp delete_document_row(%EventDocument{} = document) do
    Repo.transaction(fn ->
      case Repo.delete(document) do
        {:ok, deleted} ->
          Uploads.delete(deleted)
          deleted

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, deleted} -> {:ok, deleted}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp store_upload(upload, duty) do
    case Uploads.store(upload, duty.entity_id, duty.id) do
      {:error, :file_too_large} -> {:error, :file_too_large}
      {:error, :invalid_size} -> {:error, :invalid_size}
      file when is_map(file) -> {:ok, file}
    end
  end

  defp can_add_document?(scope, duty) do
    live_cycle?(duty) and
      (Authorization.can?(scope, :edit_duty) or
         Authorization.can?(scope, :start_progress, duty))
  end

  defp can_void_document?(scope, duty, document) do
    cond do
      locked_cycle?(duty) ->
        scope.role == :admin

      Authorization.can?(scope, :void_document) ->
        true

      document.user_id == scope.user.id and can_add_document?(scope, duty) ->
        true

      true ->
        false
    end
  end

  defp propagate_complete_documents_to_live(repo, %Scope{} = scope, %Type{} = type) do
    new_slots = type.complete_documents
    now = DateTime.utc_now(:second)

    duties =
      live(Duty)
      |> where([o], o.duty_type_id == ^type.id and o.entity_id == ^type.entity_id)
      |> where([o], o.complete_documents != ^new_slots)
      |> repo.all()

    {count, _} =
      live(Duty)
      |> where([o], o.duty_type_id == ^type.id and o.entity_id == ^type.entity_id)
      |> where([o], o.complete_documents != ^new_slots)
      |> repo.update_all(set: [complete_documents: new_slots, updated_at: now])

    Enum.each(duties, fn duty ->
      insert_audit_log!(
        repo,
        scope,
        duty,
        "complete_documents",
        duty.complete_documents,
        new_slots
      )
    end)

    {:ok, count}
  end

  defp ensure_document_on_cycle(%Duty{} = duty, %EventDocument{} = document) do
    exists? =
      EventDocument
      |> join(:inner, [d], e in Event, on: d.duty_event_id == e.id)
      |> where([d, e], d.id == ^document.id and e.duty_id == ^duty.id)
      |> Repo.exists?()

    if exists?, do: :ok, else: {:error, :not_found}
  end

  defp normalize_slot_csv(csv) do
    csv |> parse_slot_csv() |> Enum.sort() |> Enum.join(",")
  end

  defp parse_slot_csv(nil), do: []
  defp parse_slot_csv(""), do: []

  defp parse_slot_csv(csv) do
    csv
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp validate_void_reason(duty, reason) do
    if locked_cycle?(duty) and reason in [nil, ""] do
      {:error, :reason_required}
    else
      :ok
    end
  end

  defp validate_correctable(%Duty{closed_at: %DateTime{}}), do: {:error, :not_correctable}
  defp validate_correctable(%Duty{completed_at: nil}), do: {:error, :not_correctable}

  defp validate_correctable(%Duty{completed_in_error_at: %DateTime{}}),
    do: {:error, :already_corrected}

  defp validate_correctable(%Duty{}), do: :ok

  defp validate_action_note(note) when note in [nil, ""], do: {:error, :note_required}
  defp validate_action_note(_), do: :ok

  defp ensure_event_workable(%Event{} = event, %Duty{} = duty) do
    cond do
      event.duty_id != duty.id -> {:error, :not_found}
      event.status not in ["open", "in_progress"] -> {:error, :not_workable}
      true -> :ok
    end
  end

  defp validate_document_slot(_duty, slot) when slot in [nil, ""], do: :ok

  defp validate_document_slot(%Duty{} = duty, slot) when is_binary(slot) do
    required = duty.complete_documents |> parse_slot_csv() |> MapSet.new()

    cond do
      slot not in required ->
        {:error, :invalid_slot}

      slot_taken?(duty, slot) ->
        {:error, :slot_taken}

      true ->
        :ok
    end
  end

  defp slot_taken?(duty, slot) do
    duty
    |> list_cycle_documents()
    |> Enum.reject(& &1.voided_at)
    |> Enum.any?(&(&1.document_slot == slot))
  end

  defp live_cycle?(%Duty{completed_at: nil, closed_at: nil}), do: true
  defp live_cycle?(_), do: false

  defp locked_cycle?(%Duty{closed_at: %DateTime{}}), do: true
  defp locked_cycle?(%Duty{completed_at: %DateTime{}}), do: true
  defp locked_cycle?(_), do: false

  defp maybe_insert_collaborators(multi, []), do: multi

  defp maybe_insert_collaborators(multi, collaborator_ids) do
    Ecto.Multi.insert_all(multi, :collaborators, Collaborator, fn %{duty: duty} ->
      now = DateTime.utc_now(:second)

      Enum.map(collaborator_ids, fn user_id ->
        %{
          id: Ecto.UUID.generate(),
          duty_id: duty.id,
          user_id: user_id,
          inserted_at: now
        }
      end)
    end)
  end

  defp ensure_duty_entity(%Scope{entity: %{id: id}}, %Duty{entity_id: id}), do: :ok
  defp ensure_duty_entity(_, _), do: :not_found

  defp validate_duty_assignees(scope, attrs) do
    assignee = Map.get(attrs, :primary_assignee_id) || Map.get(attrs, "primary_assignee_id")
    assignee = if assignee in [nil, ""], do: nil, else: assignee

    collaborator_ids =
      Map.get(attrs, :collaborator_ids, []) || Map.get(attrs, "collaborator_ids", [])

    with :ok <- validate_entity_members(scope, List.wrap(assignee)),
         :ok <- validate_entity_members(scope, collaborator_ids) do
      :ok
    end
  end

  defp validate_assignee_change(scope, changeset) do
    case Map.get(changeset.changes, :primary_assignee_id) do
      nil -> :ok
      assignee_id -> validate_entity_members(scope, [assignee_id])
    end
  end

  defp validate_entity_members(%Scope{entity: %{id: entity_id}}, user_ids) do
    ids =
      user_ids
      |> List.wrap()
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if ids == [] do
      :ok
    else
      count =
        Membership.active()
        |> where([m], m.entity_id == ^entity_id and m.user_id in ^ids)
        |> Repo.aggregate(:count)

      if count == length(ids), do: :ok, else: {:error, :invalid_assignee}
    end
  end

  defp validate_entity_members(_, _), do: {:error, :invalid_assignee}
end
