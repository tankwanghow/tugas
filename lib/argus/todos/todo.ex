defmodule Argus.Todos.Todo do
  use Argus.Schema
  import Ecto.Changeset

  alias Argus.Accounts.User
  alias Argus.Entities.Entity
  alias Argus.Obligations.Obligation
  alias Argus.Todos.AuditLog

  @delete_window_hours 48
  @title_max 200

  schema "todos" do
    field :title, :string
    field :completed_at, :utc_datetime
    field :deleted_at, :utc_datetime
    field :canceled_at, :utc_datetime
    field :escalated_at, :utc_datetime

    belongs_to :entity, Entity
    belongs_to :created_by, User, foreign_key: :created_by_id
    belongs_to :completed_by, User, foreign_key: :completed_by_id
    belongs_to :deleted_by, User, foreign_key: :deleted_by_id
    belongs_to :canceled_by, User, foreign_key: :canceled_by_id
    belongs_to :escalated_by, User, foreign_key: :escalated_by_id
    belongs_to :escalated_obligation, Obligation, foreign_key: :escalated_obligation_id

    has_many :audit_logs, AuditLog

    timestamps(type: :utc_datetime)
  end

  def delete_window_hours, do: @delete_window_hours

  def changeset(todo, attrs) do
    todo
    |> cast(attrs, [:title])
    |> validate_required([:title])
    |> validate_length(:title, max: @title_max)
  end

  def complete_changeset(todo, user_id, at \\ DateTime.utc_now(:second)) do
    todo
    |> change(%{completed_at: at, completed_by_id: user_id})
  end

  def reopen_changeset(todo) do
    todo
    |> change(%{completed_at: nil, completed_by_id: nil})
  end

  def delete_changeset(todo, user_id, at \\ DateTime.utc_now(:second)) do
    todo
    |> change(%{deleted_at: at, deleted_by_id: user_id})
  end

  def cancel_changeset(todo, user_id, at \\ DateTime.utc_now(:second)) do
    todo
    |> change(%{canceled_at: at, canceled_by_id: user_id})
  end

  def escalate_changeset(todo, user_id, obligation_id, at \\ DateTime.utc_now(:second)) do
    todo
    |> change(%{
      escalated_at: at,
      escalated_by_id: user_id,
      escalated_obligation_id: obligation_id
    })
  end

  def completed?(%__MODULE__{completed_at: %DateTime{}}), do: true
  def completed?(_), do: false

  def escalated?(%__MODULE__{escalated_at: %DateTime{}}), do: true
  def escalated?(_), do: false

  def canceled?(%__MODULE__{canceled_at: %DateTime{}}), do: true
  def canceled?(_), do: false

  def display_status(%__MODULE__{escalated_at: %DateTime{}}), do: :escalated
  def display_status(%__MODULE__{canceled_at: %DateTime{}}), do: :canceled
  def display_status(%__MODULE__{completed_at: %DateTime{}}), do: :completed
  def display_status(_), do: :open

  def open?(%__MODULE__{} = todo) do
    active?(todo) and not completed?(todo)
  end

  def deletable?(%__MODULE__{} = todo, now \\ DateTime.utc_now(:second)) do
    open?(todo) and within_delete_window?(todo, now)
  end

  def cancelable?(%__MODULE__{} = todo, now \\ DateTime.utc_now(:second)) do
    open?(todo) and not within_delete_window?(todo, now)
  end

  def editable?(%__MODULE__{} = todo), do: open?(todo)

  def active?(%__MODULE__{
        deleted_at: nil,
        canceled_at: nil,
        escalated_at: nil
      }),
      do: true

  def active?(_), do: false

  defp within_delete_window?(%__MODULE__{inserted_at: %DateTime{} = inserted_at}, now) do
    DateTime.diff(now, inserted_at, :hour) < @delete_window_hours
  end

  defp within_delete_window?(_, _), do: false
end
