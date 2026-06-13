defmodule Argus.Obligations.Type do
  use Argus.Schema
  import Ecto.Changeset

  alias Argus.Entities.Entity
  alias Argus.Obligations.Recurrence

  schema "obligation_types" do
    field :name, :string
    field :recurring_interval, :string, default: "none"
    field :complete_note_required, :boolean, default: false
    field :complete_documents, :string, default: ""
    field :reminder_offsets, :string, default: ""

    belongs_to :entity, Entity

    timestamps()
  end

  @doc false
  def changeset(type, attrs) do
    type
    |> cast(attrs, [
      :name,
      :recurring_interval,
      :complete_note_required,
      :complete_documents,
      :reminder_offsets
    ])
    |> validate_required([:name, :recurring_interval])
    |> validate_inclusion(:recurring_interval, Recurrence.intervals())
    |> validate_reminder_offsets()
    |> validate_complete_documents()
    |> unique_constraint([:entity_id, :name])
  end

  defp validate_reminder_offsets(changeset) do
    case get_change(changeset, :reminder_offsets) do
      nil ->
        changeset

      "" ->
        changeset

      raw ->
        tokens =
          raw
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        parsed =
          Enum.reduce_while(tokens, [], fn token, acc ->
            case Integer.parse(token) do
              {n, ""} when n >= 0 -> {:cont, [n | acc]}
              _ -> {:halt, :invalid}
            end
          end)

        case parsed do
          :invalid ->
            add_error(changeset, :reminder_offsets, "must be comma-separated non-negative integers")

          nums ->
            canonical =
              nums
              |> Enum.uniq()
              |> Enum.sort()
              |> Enum.map_join(",", &Integer.to_string/1)

            put_change(changeset, :reminder_offsets, canonical)
        end
    end
  end

  defp validate_complete_documents(changeset) do
    case get_change(changeset, :complete_documents) do
      nil ->
        changeset

      "" ->
        changeset

      raw ->
        slots =
          raw
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        cond do
          length(slots) != length(Enum.uniq(slots)) ->
            add_error(changeset, :complete_documents, "has duplicate slot names")

          true ->
            canonical = Enum.uniq(slots) |> Enum.sort() |> Enum.join(",")
            put_change(changeset, :complete_documents, canonical)
        end
    end
  end
end