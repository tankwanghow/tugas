defmodule Argus.Obligations.Event do
  use Argus.Schema
  import Ecto.Changeset

  alias Argus.Accounts.User
  alias Argus.Obligations.Obligation

  schema "obligation_events" do
    field :status, :string
    field :note, :string

    belongs_to :obligation, Obligation
    belongs_to :status_by, User, foreign_key: :status_by_id

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @statuses ~w(open in_progress done cancelled)

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:status, :note])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end
end