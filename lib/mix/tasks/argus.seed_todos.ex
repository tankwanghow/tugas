defmodule Mix.Tasks.Argus.SeedTodos do
  @shortdoc "Inserts sample todos for UI testing (default: 500 on first entity)"

  @moduledoc """
  Bulk-inserts open and completed todos for exercising the todos UI.

      mix argus.seed_todos
      mix argus.seed_todos --entity my-entity-slug
      mix argus.seed_todos --count 500 --entity my-entity-slug

  Safe to re-run — each invocation adds another batch with unique titles.
  """

  use Mix.Task

  import Ecto.Query

  alias Argus.Entities.{Entity, Membership}
  alias Argus.Repo
  alias Argus.Todos.{AuditLog, Todo}

  @default_count 500
  @chunk_size 100

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
         {:ok, user_id} <- fetch_creator_id(entity) do
      inserted = insert_todos(entity, user_id, count)
      Mix.shell().info("Inserted #{inserted} todos for entity #{entity.slug} (#{entity.name}).")
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

  defp insert_todos(%Entity{id: entity_id}, user_id, count) do
    batch = System.system_time(:second)
    now = DateTime.utc_now(:second)

    1..count
    |> Enum.map(fn n ->
      id = Ecto.UUID.generate()
      completed? = rem(n, 5) == 0
      inserted_at = DateTime.add(now, -n * 3600, :second)

      %{
        id: id,
        entity_id: entity_id,
        created_by_id: user_id,
        title: "Sample todo ##{batch}-#{n}",
        completed_at: if(completed?, do: DateTime.add(inserted_at, 1800, :second), else: nil),
        completed_by_id: if(completed?, do: user_id, else: nil),
        inserted_at: inserted_at,
        updated_at: inserted_at
      }
    end)
    |> Enum.chunk_every(@chunk_size)
    |> Enum.reduce(0, fn chunk, total ->
      {:ok, chunk_count} =
        Repo.transaction(fn ->
          {count, _} = Repo.insert_all(Todo, chunk)

          audit_rows =
            Enum.map(chunk, fn row ->
              %{
                id: Ecto.UUID.generate(),
                todo_id: row.id,
                user_id: user_id,
                action: "created",
                field: nil,
                old_value: nil,
                new_value: row.title,
                inserted_at: row.inserted_at
              }
            end)

          Repo.insert_all(AuditLog, audit_rows)
          count
        end)

      total + chunk_count
    end)
  end
end
