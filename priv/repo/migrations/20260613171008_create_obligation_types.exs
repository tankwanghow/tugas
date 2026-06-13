defmodule Argus.Repo.Migrations.CreateObligationTypes do
  use Ecto.Migration

  def change do
    create table(:obligation_types, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all)
      add :name, :string, null: false
      add :recurring_interval, :string, null: false, default: "none"
      add :complete_note_required, :boolean, null: false, default: false
      add :complete_documents, :string, null: false, default: ""
      add :reminder_offsets, :string, null: false, default: ""

      timestamps(type: :utc_datetime)
    end

    create unique_index(:obligation_types, [:entity_id, :name])
  end
end