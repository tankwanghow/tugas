defmodule Argus.Todos do
  @moduledoc """
  Quick todos — entity-scoped, team-visible tasks separate from obligations.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Argus.Accounts.Scope
  alias Argus.Authorization
  alias Argus.Obligations.Obligation
  alias Argus.Repo
  alias Argus.Todos.{AuditLog, Pagination, Todo}

  @statuses ~w(open completed escalated canceled all)a
  @page_size 25

  def statuses, do: @statuses

  def list_todos(scope, opts \\ [])

  def list_todos(%Scope{} = scope, opts) do
    status = parse_status(Keyword.get(opts, :status, :open))

    with {:ok, entity} <- require_entity(scope),
         true <- Authorization.can?(scope, :view_todos) do
      todos =
        Todo
        |> entity_todos(entity.id)
        |> apply_status_filter(status)
        |> apply_status_order(status)
        |> preload([:created_by, :completed_by, :escalated_obligation])
        |> Repo.all()

      {:ok, todos}
    else
      :no_entity -> :not_authorise
      false -> :not_authorise
    end
  end

  def list_todos(_, _opts), do: :not_authorise

  def list_todos_page(scope, opts \\ [])

  def list_todos_page(%Scope{} = scope, opts) do
    status = parse_status(Keyword.get(opts, :status, :open))
    cursor = Pagination.decode(Keyword.get(opts, :cursor))
    limit = Keyword.get(opts, :limit, @page_size)

    with {:ok, entity} <- require_entity(scope),
         true <- Authorization.can?(scope, :view_todos) do
      result =
        Todo
        |> entity_todos(entity.id)
        |> apply_status_filter(status)
        |> apply_status_order(status)
        |> apply_page_cursor(status, cursor)
        |> preload([:created_by, :completed_by, :escalated_obligation])
        |> maybe_limit(limit)
        |> Repo.all()
        |> paginate(status, limit)

      {:ok, result}
    else
      :no_entity -> :not_authorise
      false -> :not_authorise
    end
  end

  def list_todos_page(_, _), do: :not_authorise

  def parse_status(:completed), do: :completed
  def parse_status(:escalated), do: :escalated
  def parse_status(:canceled), do: :canceled
  def parse_status(:all), do: :all
  def parse_status(:open), do: :open
  def parse_status("completed"), do: :completed
  def parse_status("escalated"), do: :escalated
  def parse_status("canceled"), do: :canceled
  def parse_status("all"), do: :all
  def parse_status(_), do: :open

  def get_todo(%Scope{} = scope, id) do
    with {:ok, entity} <- require_entity(scope),
         true <- Authorization.can?(scope, :view_todos),
         %Todo{} = todo <- fetch_active_todo(entity.id, id) do
      {:ok, todo}
    else
      :no_entity -> :not_authorise
      false -> :not_authorise
      nil -> :not_found
    end
  end

  def get_todo(_, _), do: :not_authorise

  def get_todo_for_escalation(%Scope{} = scope, id) do
    with {:ok, entity} <- require_entity(scope),
         true <- Authorization.can?(scope, :view_todos),
         %Todo{} = todo <- fetch_active_todo(entity.id, id) do
      if Todo.completed?(todo) do
        :not_found
      else
        {:ok, todo}
      end
    else
      :no_entity -> :not_authorise
      false -> :not_authorise
      nil -> :not_found
    end
  end

  def get_todo_for_escalation(_, _), do: :not_authorise

  def change_todo(%Todo{} = todo, attrs \\ %{}) do
    Todo.changeset(todo, attrs)
  end

  def create_todo(%Scope{} = scope, attrs) do
    with {:ok, entity} <- require_entity(scope),
         true <- Authorization.can?(scope, :create_todo) do
      Multi.new()
      |> Multi.insert(
        :todo,
        %Todo{entity_id: entity.id, created_by_id: scope.user.id}
        |> Todo.changeset(attrs)
      )
      |> Multi.run(:audit, fn repo, %{todo: todo} ->
        insert_audit!(repo, scope, todo, "created", nil, nil, todo.title)
        {:ok, :created}
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{todo: todo}} -> {:ok, todo}
        {:error, :todo, changeset, _} -> {:error, changeset}
        {:error, _op, reason, _} -> {:error, reason}
      end
    else
      :no_entity -> :not_authorise
      false -> :not_authorise
    end
  end

  def create_todo(_, _), do: :not_authorise

  def update_todo(%Scope{} = scope, %Todo{} = todo, attrs) do
    cond do
      not Authorization.can?(scope, :edit_todo) ->
        :not_authorise

      not Todo.active?(todo) ->
        :not_found

      Todo.completed?(todo) ->
        :not_found

      true ->
        changeset = Todo.changeset(todo, attrs)

        if changeset.valid? && changeset.changes == %{} do
          {:ok, todo}
        else
          Multi.new()
          |> Multi.update(:todo, changeset)
          |> Multi.run(:audit, fn repo, %{todo: updated} ->
            audit_title_change(repo, scope, todo, updated)
            {:ok, :audited}
          end)
          |> Repo.transaction()
          |> case do
            {:ok, %{todo: updated}} -> {:ok, updated}
            {:error, :todo, changeset, _} -> {:error, changeset}
            {:error, _op, reason, _} -> {:error, reason}
          end
        end
    end
  end

  def toggle_complete(%Scope{user: user} = scope, %Todo{} = todo) do
    cond do
      not Authorization.can?(scope, :complete_todo) ->
        :not_authorise

      not Todo.active?(todo) ->
        :not_found

      Todo.completed?(todo) ->
        reopen_todo(scope, todo)

      true ->
        complete_todo(scope, todo, user.id)
    end
  end

  def delete_todo(%Scope{} = scope, %Todo{} = todo) do
    cond do
      not Authorization.can?(scope, :delete_todo) ->
        :not_authorise

      not Todo.active?(todo) ->
        :not_found

      Todo.completed?(todo) ->
        {:error, :not_deletable}

      not Todo.deletable?(todo) ->
        {:error, :delete_window_expired}

      true ->
        now = DateTime.utc_now(:second)

        Multi.new()
        |> Multi.update(:todo, Todo.delete_changeset(todo, scope.user.id, now))
        |> Multi.run(:audit, fn repo, %{todo: updated} ->
          insert_audit!(repo, scope, updated, "deleted", "title", updated.title, nil)
          {:ok, :audited}
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{todo: deleted}} -> {:ok, deleted}
          {:error, _op, reason, _} -> {:error, reason}
        end
    end
  end

  def cancel_todo(%Scope{} = scope, %Todo{} = todo, note) do
    cond do
      not Authorization.can?(scope, :cancel_todo) ->
        :not_authorise

      not Todo.active?(todo) ->
        :not_found

      Todo.completed?(todo) ->
        {:error, :not_cancelable}

      Todo.deletable?(todo) ->
        {:error, :not_cancelable}

      true ->
        with :ok <- validate_action_note(note) do
          now = DateTime.utc_now(:second)

          Multi.new()
          |> Multi.update(:todo, Todo.cancel_changeset(todo, scope.user.id, now))
          |> Multi.run(:audit, fn repo, %{todo: updated} ->
            insert_audit!(repo, scope, updated, "canceled", "note", nil, note)
            {:ok, :audited}
          end)
          |> Repo.transaction()
          |> case do
            {:ok, %{todo: canceled}} -> {:ok, canceled}
            {:error, _op, reason, _} -> {:error, reason}
          end
        end
    end
  end

  def record_escalation(%Scope{} = scope, %Todo{} = todo, %Obligation{} = obligation) do
    cond do
      not Authorization.can?(scope, :create_obligation) ->
        :not_authorise

      Todo.completed?(todo) ->
        :not_found

      not Todo.active?(todo) ->
        :not_found

      todo.entity_id != obligation.entity_id ->
        {:error, :invalid_escalation}

      true ->
        now = DateTime.utc_now(:second)

        Multi.new()
        |> Multi.update(:todo, Todo.escalate_changeset(todo, scope.user.id, obligation.id, now))
        |> Multi.run(:audit, fn repo, %{todo: updated} ->
          insert_audit!(
            repo,
            scope,
            updated,
            "escalated",
            "obligation_id",
            nil,
            obligation.id
          )

          {:ok, :audited}
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{todo: escalated}} -> {:ok, escalated}
          {:error, _op, reason, _} -> {:error, reason}
        end
    end
  end

  def list_audit_logs(%Todo{} = todo) do
    AuditLog
    |> where([l], l.todo_id == ^todo.id)
    |> order_by([l], asc: l.inserted_at)
    |> preload(:user)
    |> Repo.all()
  end

  def list_entity_audit_logs(scope, limit \\ 50)

  def list_entity_audit_logs(%Scope{} = scope, limit) do
    with {:ok, entity} <- require_entity(scope),
         true <- Authorization.can?(scope, :view_todos) do
      logs =
        AuditLog
        |> join(:inner, [a], t in Todo, on: a.todo_id == t.id)
        |> where([a, t], t.entity_id == ^entity.id)
        |> order_by([a], desc: a.inserted_at)
        |> limit(^limit)
        |> preload([:user, todo: []])
        |> Repo.all()

      {:ok, logs}
    else
      :no_entity -> :not_authorise
      false -> :not_authorise
    end
  end

  def list_entity_audit_logs(_, _), do: :not_authorise

  defp complete_todo(scope, todo, user_id) do
    Multi.new()
    |> Multi.update(:todo, Todo.complete_changeset(todo, user_id))
    |> Multi.run(:audit, fn repo, %{todo: updated} ->
      insert_audit!(repo, scope, updated, "completed", nil, nil, nil)
      {:ok, :completed}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{todo: updated}} -> {:ok, updated}
      {:error, _op, reason, _} -> {:error, reason}
    end
  end

  defp reopen_todo(scope, todo) do
    Multi.new()
    |> Multi.update(:todo, Todo.reopen_changeset(todo))
    |> Multi.run(:audit, fn repo, %{todo: updated} ->
      insert_audit!(repo, scope, updated, "reopened", nil, nil, nil)
      {:ok, :reopened}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{todo: updated}} -> {:ok, updated}
      {:error, _op, reason, _} -> {:error, reason}
    end
  end

  defp audit_title_change(repo, scope, old, updated) do
    if old.title != updated.title do
      insert_audit!(repo, scope, updated, "updated", "title", old.title, updated.title)
    end

    :ok
  end

  defp insert_audit!(repo, scope, todo, action, field, old_value, new_value) do
    %AuditLog{todo_id: todo.id, user_id: scope.user.id}
    |> AuditLog.changeset(%{
      action: action,
      field: field,
      old_value: old_value,
      new_value: new_value
    })
    |> repo.insert!()
  end

  defp validate_action_note(note) when note in [nil, ""], do: {:error, :note_required}
  defp validate_action_note(_), do: :ok

  defp require_entity(%Scope{entity: %_{} = entity}), do: {:ok, entity}
  defp require_entity(_), do: :no_entity

  defp apply_status_filter(query, :open) do
    query
    |> where([t], is_nil(t.completed_at))
    |> where([t], is_nil(t.canceled_at))
    |> where([t], is_nil(t.escalated_at))
  end

  defp apply_status_filter(query, :completed) do
    query
    |> where([t], not is_nil(t.completed_at))
    |> where([t], is_nil(t.canceled_at))
    |> where([t], is_nil(t.escalated_at))
  end

  defp apply_status_filter(query, :escalated) do
    where(query, [t], not is_nil(t.escalated_at))
  end

  defp apply_status_filter(query, :canceled) do
    where(query, [t], not is_nil(t.canceled_at))
  end

  defp apply_status_filter(query, :all), do: query

  defp apply_status_order(query, :completed) do
    order_by(query, [t], desc: t.completed_at, desc: t.id)
  end

  defp apply_status_order(query, :escalated) do
    order_by(query, [t], desc: t.escalated_at, desc: t.id)
  end

  defp apply_status_order(query, :canceled) do
    order_by(query, [t], desc: t.canceled_at, desc: t.id)
  end

  defp apply_status_order(query, :open) do
    order_by(query, [t], desc: t.inserted_at, desc: t.id)
  end

  defp apply_status_order(query, :all) do
    order_by(query, [t],
      desc: is_nil(t.canceled_at) and is_nil(t.escalated_at) and is_nil(t.completed_at),
      desc: is_nil(t.canceled_at) and is_nil(t.escalated_at) and not is_nil(t.completed_at),
      desc: not is_nil(t.escalated_at),
      desc: not is_nil(t.canceled_at),
      desc: t.inserted_at,
      desc: t.id
    )
  end

  defp apply_page_cursor(query, _status, nil), do: query

  defp apply_page_cursor(query, :open, %{key: k, id: id}) do
    case DateTime.from_iso8601(k) do
      {:ok, ts, _} ->
        where(query, [t], t.inserted_at < ^ts or (t.inserted_at == ^ts and t.id < ^id))

      _ ->
        query
    end
  end

  defp apply_page_cursor(query, :completed, %{key: k, id: id}) do
    case DateTime.from_iso8601(k) do
      {:ok, ts, _} ->
        where(query, [t], t.completed_at < ^ts or (t.completed_at == ^ts and t.id < ^id))

      _ ->
        query
    end
  end

  defp apply_page_cursor(query, :escalated, %{key: k, id: id}) do
    case DateTime.from_iso8601(k) do
      {:ok, ts, _} ->
        where(query, [t], t.escalated_at < ^ts or (t.escalated_at == ^ts and t.id < ^id))

      _ ->
        query
    end
  end

  defp apply_page_cursor(query, :canceled, %{key: k, id: id}) do
    case DateTime.from_iso8601(k) do
      {:ok, ts, _} ->
        where(query, [t], t.canceled_at < ^ts or (t.canceled_at == ^ts and t.id < ^id))

      _ ->
        query
    end
  end

  defp apply_page_cursor(query, :all, %{key: k, id: id}) do
    case String.split(k, ":", parts: 2) do
      [tier_str, ts_str] ->
        with {tier, ""} <- Integer.parse(tier_str),
             {:ok, ts, _} <- DateTime.from_iso8601(ts_str) do
          where(
            query,
            [t],
            fragment(
              "(CASE WHEN ? IS NOT NULL THEN 3 WHEN ? IS NOT NULL THEN 2 WHEN ? IS NOT NULL THEN 1 ELSE 0 END) < ? OR
               ((CASE WHEN ? IS NOT NULL THEN 3 WHEN ? IS NOT NULL THEN 2 WHEN ? IS NOT NULL THEN 1 ELSE 0 END) = ? AND
                (? < ? OR (? = ? AND ? < ?)))",
              t.canceled_at,
              t.escalated_at,
              t.completed_at,
              ^tier,
              t.canceled_at,
              t.escalated_at,
              t.completed_at,
              ^tier,
              t.inserted_at,
              ^ts,
              t.inserted_at,
              ^ts,
              t.id,
              ^id
            )
          )
        else
          _ -> query
        end

      _ ->
        query
    end
  end

  defp maybe_limit(query, :all), do: query
  defp maybe_limit(query, limit), do: limit(query, ^(limit + 1))

  defp paginate(rows, _status, :all), do: %{rows: rows, cursor: nil, end?: true}

  defp paginate(rows, status, limit) do
    {page, rest} = Enum.split(rows, limit)
    has_more = rest != []

    cursor =
      if has_more do
        last = List.last(page)
        Pagination.encode(%{key: cursor_key(status, last), id: last.id})
      end

    %{rows: page, cursor: cursor, end?: not has_more}
  end

  defp cursor_key(:open, %Todo{inserted_at: ts}), do: DateTime.to_iso8601(ts)
  defp cursor_key(:completed, %Todo{completed_at: ts}), do: DateTime.to_iso8601(ts)
  defp cursor_key(:escalated, %Todo{escalated_at: ts}), do: DateTime.to_iso8601(ts)
  defp cursor_key(:canceled, %Todo{canceled_at: ts}), do: DateTime.to_iso8601(ts)

  defp cursor_key(:all, %Todo{} = todo) do
    "#{all_tier(todo)}:#{DateTime.to_iso8601(todo.inserted_at)}"
  end

  defp all_tier(%Todo{canceled_at: %DateTime{}}), do: 3
  defp all_tier(%Todo{escalated_at: %DateTime{}}), do: 2
  defp all_tier(%Todo{completed_at: %DateTime{}}), do: 1
  defp all_tier(_), do: 0

  defp entity_todos(query, entity_id) do
    query
    |> where([t], t.entity_id == ^entity_id)
    |> where([t], is_nil(t.deleted_at))
  end

  defp workable_todos(query, entity_id) do
    query
    |> entity_todos(entity_id)
    |> where([t], is_nil(t.canceled_at))
    |> where([t], is_nil(t.escalated_at))
  end

  defp fetch_active_todo(entity_id, id) do
    Todo
    |> workable_todos(entity_id)
    |> where([t], t.id == ^id)
    |> preload([:created_by, :completed_by])
    |> Repo.one()
  end
end
