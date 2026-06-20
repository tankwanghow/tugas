defmodule Argus.Obligations.Event do
  use Argus.Schema
  import Ecto.Changeset

  alias Argus.Accounts.User
  alias Argus.Obligations.{EventDocument, Obligation}

  schema "obligation_events" do
    field :status, :string
    field :note, :string

    belongs_to :obligation, Obligation
    belongs_to :status_by, User, foreign_key: :status_by_id
    has_many :documents, EventDocument, foreign_key: :obligation_event_id

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @statuses ~w(open in_progress done cancelled skipped series_ended)
  @terminal_statuses ~w(done cancelled skipped series_ended)

  @doc "Statuses that close a cycle (no further progress allowed)."
  def terminal_statuses, do: @terminal_statuses

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:status, :note])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end
end
