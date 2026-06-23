defmodule Argus.Repo.Migrations.AddObligationSortIndexes do
  use Ecto.Migration

  def change do
    create index(:obligations, [:entity_id, :due_by, :id])

    create index(:obligations, [:entity_id, :due_by, :id],
             name: :obligations_completed_due_idx,
             where: "completed_at IS NOT NULL"
           )

    create index(:obligations, [:entity_id, :due_by, :id],
             name: :obligations_skipped_due_idx,
             where: "closed_at IS NOT NULL"
           )
  end
end
