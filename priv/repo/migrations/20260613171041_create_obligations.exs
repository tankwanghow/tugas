defmodule Argus.Repo.Migrations.CreateObligations do
  use Ecto.Migration

  def change do
    create table(:obligations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all), null: false
      add :obligation_type_id, references(:obligation_types, type: :binary_id, on_delete: :restrict),
        null: false

      add :series_id, :binary_id, null: false
      add :title, :string, null: false
      add :primary_assignee_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :due_by, :date, null: false
      add :status, :string, null: false, default: "active"
      add :completed_at, :utc_datetime
      add :series_ended_at, :utc_datetime
      add :complete_note_required, :boolean, null: false, default: false
      add :complete_documents, :string, null: false, default: ""

      timestamps(type: :utc_datetime)
    end

    create index(:obligations, [:entity_id, :status])
    create index(:obligations, [:series_id])
    create index(:obligations, [:primary_assignee_id])

    create unique_index(:obligations, [:series_id],
      where: "status = 'active' AND completed_at IS NULL",
      name: :obligations_one_live_cycle_per_series
    )

    create index(:obligations, [:series_id],
      where: "series_ended_at IS NOT NULL",
      name: :obligations_series_ended
    )

    create table(:obligation_collaborators, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :obligation_id, references(:obligations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:obligation_collaborators, [:obligation_id, :user_id])

    create table(:obligation_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :obligation_id, references(:obligations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :status, :string, null: false
      add :status_by_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false
      add :note, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:obligation_events, [:obligation_id])
  end
end