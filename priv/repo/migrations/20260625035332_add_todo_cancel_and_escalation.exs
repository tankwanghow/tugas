defmodule Argus.Repo.Migrations.AddTodoCancelAndEscalation do
  use Ecto.Migration

  def change do
    alter table(:todos) do
      add :canceled_at, :utc_datetime
      add :canceled_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :escalated_obligation_id,
          references(:obligations, type: :binary_id, on_delete: :nilify_all)

      add :escalated_at, :utc_datetime
      add :escalated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:todos, [:escalated_obligation_id])
  end
end
