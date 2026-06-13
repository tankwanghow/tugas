defmodule Argus.Obligations.Collaborator do
  use Argus.Schema
  import Ecto.Changeset

  alias Argus.Accounts.User
  alias Argus.Obligations.Obligation

  schema "obligation_collaborators" do
    belongs_to :obligation, Obligation
    belongs_to :user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(collaborator, attrs \\ %{}) do
    collaborator
    |> cast(attrs, [])
    |> validate_required([])
  end
end