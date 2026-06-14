defmodule Argus.Obligations do
  @moduledoc """
  Obligations domain — cycles, events, and workflow.
  """

  import Ecto.Query, warn: false

  alias Argus.Accounts.{Scope, User}
  alias Argus.Authorization

  alias Argus.Obligations.{
    AuditLog,
    Collaborator,
    Completion,
    Event,
    EventDocument,
    Obligation,
    Recurrence,
    Series,
    Type
  }

  alias Argus.Repo
  alias Argus.Uploads

  def live(query \\ Obligation) do
    from(o in query, where: o.status == "active" and is_nil(o.completed_at))
  end

  def list_my_work(scope), do: list_obligations(scope, status: :my_live)

  def list_types(%Scope{entity: entity}) do
    Type
    |> where([t], is_nil(t.entity_id) or t.entity_id == ^entity.id)
    |> order_by([t], asc: t.name)
    |> Repo.all()
  end

  @doc """
  Fetches a type visible to the scope — either a system preset (`entity_id`
  is nil) or one owned by the scope's entity. Raises if not found/visible.
  """
  def get_type!(%Scope{entity: entity}, id) do
    Type
    |> where([t], t.id == ^id and (is_nil(t.entity_id) or t.entity_id == ^entity.id))
    |> Repo.one!()
  end

  def change_type(%Type{} = type, attrs \\ %{}), do: Type.changeset(type, attrs)

  def create_type(%Scope{entity: entity} = scope, attrs) do
    if Authorization.can?(scope, :manage_types) do
      %Type{entity_id: entity.id}
      |> Type.changeset(attrs)
      |> Repo.insert()
    else
      :not_authorise
    end
  end

  @doc """
  Updates a **custom** (entity-owned) type. System presets are immutable —
  attempting to edit one (or another entity's type) returns `:not_authorise`.
  """
  def update_type(%Scope{entity: entity} = scope, %Type{} = type, attrs) do
    if Authorization.can?(scope, :manage_types) and type.entity_id == entity.id do
      type
      |> Type.changeset(attrs)
      |> Repo.update()
    else
      :not_authorise
    end
  end

  def get_obligation!(%Scope{entity: entity}, id) do
    Obligation
    |> where([o], o.id == ^id and o.entity_id == ^entity.id)
    |> preload([
      :obligation_type,
      :primary_assignee,
      [collaborators: :user],
      [events: [:documents, :status_by]]
    ])
    |> Repo.one!()
  end

  def change_obligation(%Obligation{} = obligation, attrs \\ %{}) do
    Obligation.changeset(obligation, attrs)
  end

  def list_team_overview(scope), do: list_obligations(scope, status: :live)

  @status_filters ~w(my_live my_completed live completed cancelled all)a

  @doc """
  Lists obligations for the entity scope.

  Options:
    * `:status` — `:my_live`, `:my_completed`, `:live` (default), `:completed`,
      `:cancelled`, or `:all`. My filters scope to primary assignee or collaborator.
    * `:query` — optional case-insensitive search on title, type name, assignee email
  """
  def list_obligations(%Scope{entity: entity, user: user}, opts \\ []) do
    status = Keyword.get(opts, :status, :live)
    query = Keyword.get(opts, :query)

    unless status in @status_filters do
      raise ArgumentError, "invalid status filter #{inspect(status)}"
    end

    Obligation
    |> where([o], o.entity_id == ^entity.id)
    |> scope_to_assignee(status, user)
    |> apply_status_filter(status)
    |> apply_list_order(status)
    |> preload([:obligation_type, :primary_assignee])
    |> Repo.all()
    |> filter_by_query(query)
  end

  defp scope_to_assignee(query, status, user) when status in [:my_live, :my_completed] do
    collaborator_ids = collaborator_obligation_ids(user.id)

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

  defp apply_status_filter(query, :cancelled) do
    from o in query, where: o.status == "cancelled"
  end

  defp apply_status_filter(query, :all), do: query

  defp apply_list_order(query, status) when status in [:live, :my_live],
    do: order_by(query, [o], asc: o.due_by)

  defp apply_list_order(query, status) when status in [:completed, :my_completed],
    do: order_by(query, [o], desc: o.completed_at)

  defp apply_list_order(query, _), do: order_by(query, [o], desc: o.due_by)

  defp filter_by_query(obligations, query) when query in [nil, ""], do: obligations

  defp filter_by_query(obligations, query) do
    q = String.downcase(query)

    Enum.filter(obligations, fn obligation ->
      String.contains?(String.downcase(obligation.title), q) or
        String.contains?(String.downcase(obligation.obligation_type.name), q) or
        String.contains?(String.downcase(obligation.primary_assignee.email), q)
    end)
  end

  defp collaborator_obligation_ids(user_id) do
    from c in Collaborator, where: c.user_id == ^user_id, select: c.obligation_id
  end

  @doc """
  All cycles sharing a `series_id`, oldest first — the recurrence history.
  """
  def list_series(series_id) do
    Obligation
    |> where([o], o.series_id == ^series_id)
    |> order_by([o], asc: o.due_by)
    |> Repo.all()
  end

  def list_events(%Obligation{} = obligation) do
    Event
    |> where([e], e.obligation_id == ^obligation.id)
    |> order_by([e], asc: e.inserted_at)
    |> Repo.all()
  end

  def latest_event(%Obligation{} = obligation) do
    Event
    |> where([e], e.obligation_id == ^obligation.id)
    |> order_by([e],
      desc: e.inserted_at,
      desc:
        fragment(
          "CASE ? WHEN 'done' THEN 4 WHEN 'in_progress' THEN 3 WHEN 'cancelled' THEN 2 WHEN 'open' THEN 1 ELSE 0 END",
          e.status
        )
    )
    |> limit(1)
    |> Repo.one!()
  end

  def create_obligation(%Scope{} = scope, attrs) do
    with true <- Authorization.can?(scope, :create_obligation),
         {:ok, type} <- fetch_type_for_entity(scope, attrs),
         {:ok, obligation} <- insert_obligation(scope, attrs, type) do
      {:ok, obligation}
    else
      false -> :not_authorise
      {:error, _} = error -> error
    end
  end

  def start_progress(%Scope{} = scope, %Obligation{} = obligation) do
    obligation = Repo.preload(obligation, :collaborators)

    with true <- Authorization.can?(scope, :start_progress, obligation),
         :ok <- ensure_latest_open(obligation),
         {:ok, event} <- insert_progress_event(scope, obligation) do
      {:ok, event}
    else
      false -> :not_authorise
      {:error, _} = error -> error
    end
  end

  def list_cycle_documents(%Obligation{} = obligation) do
    EventDocument
    |> join(:inner, [d], e in Event, on: d.obligation_event_id == e.id)
    |> where([d, e], e.obligation_id == ^obligation.id)
    |> Repo.all()
  end

  def get_document!(id) do
    Repo.get!(EventDocument, id)
  end

  def add_document(
        %Scope{} = scope,
        %Obligation{} = obligation,
        %Event{} = event,
        upload,
        document_slot
      ) do
    obligation = Repo.preload(obligation, :collaborators)

    with true <- can_add_document?(scope, obligation),
         :ok <- ensure_event_workable(event, obligation),
         file = Uploads.store(upload, obligation.entity_id, obligation.id),
         {:ok, document} <- insert_document(scope, event, file, document_slot) do
      {:ok, document}
    else
      false -> :not_authorise
      {:error, _} = error -> error
    end
  end

  def list_audit_logs(%Obligation{} = obligation) do
    AuditLog
    |> where([l], l.obligation_id == ^obligation.id)
    |> order_by([l], asc: l.inserted_at)
    |> preload(:user)
    |> Repo.all()
  end

  def update_obligation(%Scope{} = scope, %Obligation{} = obligation, attrs) do
    with true <- Authorization.can?(scope, :edit_obligation),
         true <- live_cycle?(obligation) do
      changeset = Obligation.changeset(obligation, attrs)

      cond do
        not changeset.valid? -> {:error, changeset}
        changeset.changes == %{} -> {:ok, obligation}
        true -> apply_obligation_update(scope, obligation, changeset)
      end
    else
      false -> :not_authorise
    end
  end

  def update_collaborators(%Scope{} = scope, %Obligation{} = obligation, user_ids) do
    with true <- Authorization.can?(scope, :edit_obligation),
         true <- live_cycle?(obligation) do
      current =
        Collaborator
        |> where([c], c.obligation_id == ^obligation.id)
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
            obligation,
            "collaborators",
            nil,
            assignee_label(user_id)
          )
        end)

        Enum.each(to_remove, fn user_id ->
          insert_audit_log!(
            repo,
            scope,
            obligation,
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
            obligation_id: obligation.id,
            user_id: user_id,
            inserted_at: now
          }
        end)
      end)
      |> Ecto.Multi.delete_all(:removed, fn _ ->
        from c in Collaborator,
          where: c.obligation_id == ^obligation.id and c.user_id in ^to_remove
      end)
      |> Repo.transaction()
      |> case do
        {:ok, _} -> {:ok, Repo.preload(obligation, :collaborators, force: true)}
        {:error, _, reason, _} -> {:error, reason}
      end
    else
      false -> :not_authorise
    end
  end

  @doc """
  True when `scope` may correct `event.note` on a live cycle (author within 48h, or manager/admin).
  """
  def note_editable?(%Scope{} = scope, %Event{} = event, %Obligation{} = obligation) do
    can_edit_note?(scope, event, obligation)
  end

  @doc """
  True when `scope` may void a non-voided document on this obligation cycle.
  """
  def document_voidable?(
        %Scope{} = scope,
        %Obligation{} = obligation,
        %EventDocument{} = document
      ) do
    is_nil(document.voided_at) and can_void_document?(scope, obligation, document)
  end

  @doc """
  True when voiding a document on this cycle requires a reason (admin on a locked cycle).
  """
  def document_void_reason_required?(%Obligation{} = obligation) do
    locked_cycle?(obligation)
  end

  def edit_note(%Scope{} = scope, %Event{} = event, attrs) do
    obligation = Repo.get!(Obligation, event.obligation_id)
    note = Map.get(attrs, :note) || Map.get(attrs, "note")

    with true <- can_edit_note?(scope, event, obligation) do
      old_note = event.note

      Ecto.Multi.new()
      |> Ecto.Multi.update(:event, Event.changeset(event, %{note: note}))
      |> Ecto.Multi.run(:audit, fn repo, %{event: updated} ->
        if old_note != updated.note do
          insert_audit_log!(repo, scope, obligation, "note", old_note, updated.note, updated)
        end

        {:ok, :logged}
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{event: event}} -> {:ok, event}
        {:error, :event, changeset, _} -> {:error, changeset}
      end
    else
      false -> {:error, :locked}
    end
  end

  def void_document(
        %Scope{} = scope,
        %Obligation{} = obligation,
        %EventDocument{} = document,
        attrs
      ) do
    reason = Map.get(attrs, :reason) || Map.get(attrs, "reason")

    with true <- can_void_document?(scope, obligation, document),
         :ok <- validate_void_reason(obligation, reason),
         {:ok, voided} <- void_document_row(scope, document, reason) do
      {:ok, voided}
    else
      false -> :not_authorise
      {:error, _} = error -> error
    end
  end

  def complete(%Scope{} = scope, %Obligation{} = obligation, attrs) do
    obligation = Repo.preload(obligation, [:collaborators, :obligation_type])
    cycle_documents = list_cycle_documents(obligation)

    with true <- Authorization.can?(scope, :mark_done, obligation),
         :ok <- Completion.validate_done_requirements(obligation, attrs, cycle_documents),
         :ok <- validate_next_due(obligation, attrs),
         {:ok, completed, spawned} <- complete_multi(scope, obligation, attrs) do
      {:ok, completed, spawned}
    else
      false -> :not_authorise
      {:error, _} = error -> error
    end
  end

  def cancel_obligation(%Scope{} = scope, %Obligation{} = obligation, attrs) do
    note = Map.get(attrs, :note) || Map.get(attrs, "note")

    with true <- Authorization.can?(scope, :cancel_obligation),
         :ok <- validate_action_note(note) do
      now = DateTime.utc_now(:second)

      Ecto.Multi.new()
      |> Ecto.Multi.update_all(
        :obligation,
        live(Obligation) |> where([o], o.id == ^obligation.id),
        set: [status: "cancelled", updated_at: now]
      )
      |> Ecto.Multi.run(:check, fn _repo, %{obligation: {count, _}} ->
        if count == 1, do: {:ok, :updated}, else: {:error, :not_live}
      end)
      |> Ecto.Multi.insert(:cancelled_event, fn _ ->
        %Event{
          obligation_id: obligation.id,
          status_by_id: scope.user.id
        }
        |> Event.changeset(%{status: "cancelled", note: note})
      end)
      |> Repo.transaction()
      |> case do
        {:ok, _} ->
          {:ok, Repo.get!(Obligation, obligation.id)}

        {:error, :check, :not_live, _} ->
          {:error, :not_live}

        {:error, :cancelled_event, changeset, _} ->
          {:error, changeset}
      end
    else
      false -> :not_authorise
      {:error, _} = error -> error
    end
  end

  def end_series(%Scope{} = scope, %Obligation{} = obligation, attrs) do
    note = Map.get(attrs, :note) || Map.get(attrs, "note")

    with true <- Authorization.can?(scope, :end_series),
         :ok <- validate_action_note(note) do
      now = DateTime.utc_now(:second)

      Ecto.Multi.new()
      |> Ecto.Multi.update_all(
        :obligation,
        live(Obligation) |> where([o], o.id == ^obligation.id),
        set: [status: "cancelled", series_ended_at: now, updated_at: now]
      )
      |> Ecto.Multi.run(:check, fn _repo, %{obligation: {count, _}} ->
        if count == 1, do: {:ok, :updated}, else: {:error, :not_live}
      end)
      |> Ecto.Multi.insert(:cancelled_event, fn _ ->
        %Event{
          obligation_id: obligation.id,
          status_by_id: scope.user.id
        }
        |> Event.changeset(%{status: "cancelled", note: note})
      end)
      |> Repo.transaction()
      |> case do
        {:ok, _} ->
          {:ok, Repo.get!(Obligation, obligation.id)}

        {:error, :check, :not_live, _} ->
          {:error, :not_live}

        {:error, :cancelled_event, changeset, _} ->
          {:error, changeset}
      end
    else
      false -> :not_authorise
      {:error, _} = error -> error
    end
  end

  defp complete_multi(scope, obligation, attrs) do
    now = DateTime.utc_now(:second)
    next_due_by = Map.get(attrs, :next_due_by) || Map.get(attrs, "next_due_by")
    note = Map.get(attrs, :note) || Map.get(attrs, "note")
    spawn? = should_spawn_next?(obligation, next_due_by)

    Ecto.Multi.new()
    |> Ecto.Multi.update_all(
      :close,
      live(Obligation) |> where([o], o.id == ^obligation.id),
      set: [completed_at: now, updated_at: now]
    )
    |> Ecto.Multi.run(:check_live, fn _repo, %{close: {count, _}} ->
      if count == 1, do: {:ok, :closed}, else: {:error, :not_live}
    end)
    |> Ecto.Multi.insert(:done_event, fn _ ->
      %Event{
        obligation_id: obligation.id,
        status_by_id: scope.user.id
      }
      |> Event.changeset(%{status: "done", note: note})
    end)
    |> Ecto.Multi.run(:spawn, fn repo, %{close: {_, _}} ->
      if spawn? do
        case spawn_next_cycle(repo, obligation, next_due_by) do
          {:ok, new_obligation} -> {:ok, new_obligation}
          {:error, reason} -> {:error, reason}
        end
      else
        {:ok, nil}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{spawn: new_obligation}} ->
        {:ok, Repo.get!(Obligation, obligation.id), new_obligation}

      {:error, :check_live, :not_live, _} ->
        {:error, :not_live}

      {:error, :spawn, :not_live, _} ->
        {:error, :not_live}

      {:error, :done_event, changeset, _} ->
        {:error, changeset}
    end
  end

  defp should_spawn_next?(%Obligation{} = obligation, next_due_by) do
    Recurrence.recurring?(obligation.obligation_type) and not Series.ended?(obligation.series_id) and
      not is_nil(next_due_by)
  end

  defp validate_next_due(%Obligation{} = obligation, attrs) do
    next_due_by = Map.get(attrs, :next_due_by) || Map.get(attrs, "next_due_by")
    type = obligation.obligation_type || Repo.get!(Type, obligation.obligation_type_id)

    if Recurrence.recurring?(type) and not Series.ended?(obligation.series_id) and
         next_due_by in [nil, ""] do
      {:error, :next_due_required}
    else
      :ok
    end
  end

  defp spawn_next_cycle(repo, %Obligation{} = done_obligation, next_due_by) do
    type = Repo.get!(Type, done_obligation.obligation_type_id)

    collaborators =
      Repo.all(from c in Collaborator, where: c.obligation_id == ^done_obligation.id)

    now = DateTime.utc_now(:second)

    obligation_changeset =
      %Obligation{
        entity_id: done_obligation.entity_id,
        series_id: done_obligation.series_id,
        status: "active",
        complete_note_required: type.complete_note_required,
        complete_documents: type.complete_documents
      }
      |> Obligation.changeset(%{
        title: done_obligation.title,
        obligation_type_id: done_obligation.obligation_type_id,
        primary_assignee_id: done_obligation.primary_assignee_id,
        due_by: next_due_by
      })

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:obligation, obligation_changeset)
    |> Ecto.Multi.insert_all(:collaborators, Collaborator, fn %{obligation: obligation} ->
      Enum.map(collaborators, fn c ->
        %{
          id: Ecto.UUID.generate(),
          obligation_id: obligation.id,
          user_id: c.user_id,
          inserted_at: now
        }
      end)
    end)
    |> Ecto.Multi.insert(:open_event, fn %{obligation: obligation} ->
      %Event{
        obligation_id: obligation.id,
        status_by_id: done_obligation.primary_assignee_id
      }
      |> Event.changeset(%{status: "open"})
    end)
    |> repo.transaction()
    |> case do
      {:ok, %{obligation: obligation}} ->
        {:ok, obligation}

      {:error, :obligation, %Ecto.Changeset{errors: errors}, _} ->
        if constraint_error?(errors, :series_id),
          do: {:error, :not_live},
          else: {:error, :invalid}

      {:error, _, reason, _} ->
        {:error, reason}
    end
  end

  defp constraint_error?(errors, field) do
    Enum.any?(errors, fn
      {^field, {_msg, [constraint: :unique, constraint_name: _]}} -> true
      _ -> false
    end)
  end

  defp ensure_latest_open(%Obligation{} = obligation) do
    forward_step? =
      Event
      |> where([e], e.obligation_id == ^obligation.id and e.status != "open")
      |> Repo.exists?()

    if forward_step?, do: {:error, :not_open}, else: :ok
  end

  defp insert_progress_event(%Scope{user: user}, %Obligation{} = obligation) do
    %Event{
      obligation_id: obligation.id,
      status_by_id: user.id
    }
    |> Event.changeset(%{status: "in_progress"})
    |> Repo.insert()
  end

  defp fetch_type_for_entity(%Scope{entity: entity}, attrs) do
    type_id = Map.get(attrs, :obligation_type_id) || Map.get(attrs, "obligation_type_id")

    case Repo.get(Type, type_id) do
      %Type{entity_id: nil} = type -> {:ok, type}
      %Type{entity_id: entity_id} = type when entity_id == entity.id -> {:ok, type}
      %Type{} -> {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  defp insert_obligation(%Scope{user: user, entity: entity}, attrs, %Type{} = type) do
    series_id = Ecto.UUID.generate()
    open_note = Map.get(attrs, :open_note) || Map.get(attrs, "open_note")

    collaborator_ids =
      Map.get(attrs, :collaborator_ids, []) || Map.get(attrs, "collaborator_ids", [])

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:obligation, fn _ ->
      %Obligation{
        entity_id: entity.id,
        series_id: series_id,
        status: "active",
        complete_note_required: type.complete_note_required,
        complete_documents: type.complete_documents
      }
      |> Obligation.changeset(attrs)
    end)
    |> maybe_insert_collaborators(collaborator_ids)
    |> Ecto.Multi.insert(:open_event, fn %{obligation: obligation} ->
      %Event{
        obligation_id: obligation.id,
        status_by_id: user.id
      }
      |> Event.changeset(%{status: "open", note: open_note})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{obligation: obligation}} -> {:ok, obligation}
      {:error, :obligation, changeset, _} -> {:error, changeset}
      {:error, :open_event, changeset, _} -> {:error, changeset}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  defp apply_obligation_update(scope, obligation, changeset) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:obligation, changeset)
    |> Ecto.Multi.run(:audit, fn repo, %{obligation: updated} ->
      Enum.each(changeset.changes, fn {field, new_value} ->
        old_value = Map.get(obligation, field)
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
      {:ok, %{obligation: obligation}} -> {:ok, obligation}
      {:error, :obligation, changeset, _} -> {:error, changeset}
    end
  end

  defp insert_audit_log!(repo, scope, obligation, field, old_value, new_value, event \\ nil) do
    %AuditLog{
      obligation_id: obligation.id,
      obligation_event_id: event && event.id,
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

  defp can_edit_note?(scope, event, obligation) do
    cond do
      locked_cycle?(obligation) -> false
      Authorization.can?(scope, :edit_obligation) -> true
      event.status_by_id == scope.user.id and within_note_window?(event) -> true
      true -> false
    end
  end

  defp within_note_window?(%Event{inserted_at: inserted_at}) do
    DateTime.diff(DateTime.utc_now(:second), inserted_at, :second) <= 48 * 3600
  end

  defp insert_document(%Scope{user: user}, %Event{} = event, file, document_slot) do
    %EventDocument{
      obligation_event_id: event.id,
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

  defp can_add_document?(scope, obligation) do
    live_cycle?(obligation) and
      (Authorization.can?(scope, :edit_obligation) or
         Authorization.can?(scope, :start_progress, obligation))
  end

  defp can_void_document?(scope, obligation, document) do
    cond do
      locked_cycle?(obligation) ->
        scope.role == :admin

      Authorization.can?(scope, :void_document) ->
        true

      document.user_id == scope.user.id and can_add_document?(scope, obligation) ->
        true

      true ->
        false
    end
  end

  defp validate_void_reason(obligation, reason) do
    if locked_cycle?(obligation) and reason in [nil, ""] do
      {:error, :reason_required}
    else
      :ok
    end
  end

  defp validate_action_note(note) when note in [nil, ""], do: {:error, :note_required}
  defp validate_action_note(_), do: :ok

  defp ensure_event_workable(%Event{} = event, %Obligation{} = obligation) do
    cond do
      event.obligation_id != obligation.id -> {:error, :not_found}
      event.status not in ["open", "in_progress"] -> {:error, :not_workable}
      true -> :ok
    end
  end

  defp live_cycle?(%Obligation{status: "active", completed_at: nil}), do: true
  defp live_cycle?(_), do: false

  defp locked_cycle?(%Obligation{status: "cancelled"}), do: true
  defp locked_cycle?(%Obligation{completed_at: %DateTime{}}), do: true
  defp locked_cycle?(_), do: false

  defp maybe_insert_collaborators(multi, []), do: multi

  defp maybe_insert_collaborators(multi, collaborator_ids) do
    Ecto.Multi.insert_all(multi, :collaborators, Collaborator, fn %{obligation: obligation} ->
      now = DateTime.utc_now(:second)

      Enum.map(collaborator_ids, fn user_id ->
        %{
          id: Ecto.UUID.generate(),
          obligation_id: obligation.id,
          user_id: user_id,
          inserted_at: now
        }
      end)
    end)
  end
end
