defmodule Mix.Tasks.Tugas.SeedDuties do
  @shortdoc "Inserts sample live duties for UI testing"

  @moduledoc """
  Bulk-inserts live duties (with open events) for exercising the dashboard calendar.

      mix tugas.seed_duties
      mix tugas.seed_duties --entity my-entity-slug
      mix tugas.seed_duties --count 500 --entity my-entity-slug

  Safe to re-run — each invocation adds another batch with unique titles.
  """

  use Mix.Task

  import Ecto.Query

  alias Tugas.Duties.{Duty, Event, Type}
  alias Tugas.Entities.{Entity, Membership}
  alias Tugas.Repo

  @default_count 500
  @chunk_size 50
  @someday_every 10

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [entity: :string, count: :integer]
      )

    count = Keyword.get(opts, :count, @default_count)
    entity_slug = Keyword.get(opts, :entity)

    with {:ok, entity} <- fetch_entity(entity_slug),
         {:ok, user_id} <- fetch_creator_id(entity),
         {:ok, types} <- fetch_types(entity),
         {:ok, assignee_ids} <- fetch_assignee_ids(entity) do
      inserted = insert_duties(entity, user_id, types, assignee_ids, count)
      Mix.shell().info("Inserted #{inserted} duties for entity #{entity.slug} (#{entity.name}).")
    else
      {:error, message} ->
        Mix.raise(message)
    end
  end

  defp fetch_entity(nil) do
    case Repo.one(
           from(e in Entity,
             where: is_nil(e.deleted_at),
             order_by: [asc: e.inserted_at],
             limit: 1
           )
         ) do
      %Entity{} = entity -> {:ok, entity}
      nil -> {:error, "No entity found. Create an entity first or pass --entity SLUG."}
    end
  end

  defp fetch_entity(slug) do
    case Repo.one(from(e in Entity, where: e.slug == ^slug and is_nil(e.deleted_at))) do
      %Entity{} = entity -> {:ok, entity}
      nil -> {:error, "Entity not found for slug #{inspect(slug)}"}
    end
  end

  defp fetch_creator_id(%Entity{id: entity_id}) do
    case Repo.one(
           from(m in Membership,
             where: m.entity_id == ^entity_id,
             order_by: [asc: m.inserted_at],
             limit: 1,
             select: m.user_id
           )
         ) do
      id when is_binary(id) -> {:ok, id}
      nil -> {:error, "No membership found for entity — add a member first."}
    end
  end

  defp fetch_types(%Entity{id: entity_id}) do
    types = Repo.all(from(t in Type, where: t.entity_id == ^entity_id, order_by: [asc: t.name]))

    case types do
      [] -> {:error, "No duty types found for entity — create types first."}
      _ -> {:ok, types}
    end
  end

  defp fetch_assignee_ids(%Entity{id: entity_id}) do
    ids =
      Repo.all(
        from(m in Membership,
          where:
            m.entity_id == ^entity_id and not is_nil(m.accepted_at) and is_nil(m.disabled_at),
          select: m.user_id
        )
      )

    {:ok, ids}
  end

  defp insert_duties(%Entity{id: entity_id}, user_id, types, assignee_ids, count) do
    batch = System.system_time(:second)
    now = DateTime.utc_now(:second)
    today = Date.utc_today()
    type_count = length(types)

    1..count
    |> Enum.map(fn n ->
      type = Enum.at(types, rem(n, type_count))
      duty_id = Ecto.UUID.generate()
      series_id = Ecto.UUID.generate()
      inserted_at = DateTime.add(now, -n * 1800, :second)
      someday? = rem(n, @someday_every) == 0

      due_by =
        if someday? do
          nil
        else
          Date.add(today, rem(n * 3, 120) - 30)
        end

      assignee_id =
        case assignee_ids do
          [] -> nil
          ids -> Enum.at(ids, rem(n, length(ids)))
        end

      duty = %{
        id: duty_id,
        entity_id: entity_id,
        series_id: series_id,
        duty_type_id: type.id,
        title: "Sample duty ##{batch}-#{n}",
        due_by: due_by,
        primary_assignee_id: assignee_id,
        complete_documents: type.complete_documents,
        inserted_at: inserted_at,
        updated_at: inserted_at
      }

      event = %{
        id: Ecto.UUID.generate(),
        duty_id: duty_id,
        status: "open",
        note: "Seeded for dashboard testing",
        status_by_id: user_id,
        inserted_at: inserted_at
      }

      {duty, event}
    end)
    |> Enum.chunk_every(@chunk_size)
    |> Enum.reduce(0, fn chunk, total ->
      {:ok, chunk_count} =
        Repo.transaction(fn ->
          duties = Enum.map(chunk, fn {duty, _} -> duty end)
          events = Enum.map(chunk, fn {_, event} -> event end)

          {duty_count, _} = Repo.insert_all(Duty, duties)
          Repo.insert_all(Event, events)
          duty_count
        end)

      total + chunk_count
    end)
  end
end