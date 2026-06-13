defmodule Argus.Obligations.Obligation do
  use Argus.Schema
  import Ecto.Changeset

  alias Argus.Accounts.User
  alias Argus.Entities.Entity
  alias Argus.Obligations.{Collaborator, Event, Type}

  schema "obligations" do
    field :series_id, :binary_id
    field :title, :string
    field :due_by, :date
    field :status, :string, default: "active"
    field :completed_at, :utc_datetime
    field :series_ended_at, :utc_datetime
    field :complete_note_required, :boolean, default: false
    field :complete_documents, :string, default: ""
    field :open_note, :string, virtual: true

    belongs_to :entity, Entity
    belongs_to :obligation_type, Type
    belongs_to :primary_assignee, User, foreign_key: :primary_assignee_id

    has_many :events, Event
    has_many :collaborators, Collaborator

    timestamps()
  end

  @cast_fields ~w(title obligation_type_id primary_assignee_id due_by open_note)a

  @doc false
  def changeset(obligation, attrs) do
    obligation
    |> cast(attrs, @cast_fields)
    |> validate_required([:title, :obligation_type_id, :primary_assignee_id, :due_by])
    |> validate_inclusion(:status, ["active", "cancelled"])
    |> unique_constraint(:series_id, name: :obligations_one_live_cycle_per_series)
  end
end
