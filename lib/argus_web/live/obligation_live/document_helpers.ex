defmodule ArgusWeb.ObligationLive.DocumentHelpers do
  @moduledoc false

  @uploadable_statuses ~w(open in_progress)

  @doc """
  Returns the best timeline event for attaching documents (in_progress preferred, then open).
  """
  def upload_event(events) when is_list(events) do
    events
    |> Enum.filter(&(&1.status in @uploadable_statuses))
    |> Enum.sort_by(& &1.inserted_at, DateTime)
    |> pick_upload_event()
  end

  defp pick_upload_event([]), do: nil

  defp pick_upload_event(events) do
    Enum.find_value(~w(in_progress open), fn status ->
      events
      |> Enum.filter(&(&1.status == status))
      |> List.last()
    end)
  end

  @doc """
  Classifies an uploaded file by its filename extension into a preview kind:
  `:image`, `:video`, `:pdf`, or `:other` (no inline preview — download only).
  """
  def file_kind(name), do: Argus.Uploads.FileKind.classify(name)

  def cycle_documents(%{events: events}) when is_list(events) do
    Enum.flat_map(events, & &1.documents)
  end

  def find_event(events, event_id) when is_list(events) do
    Enum.find(events, &(to_string(&1.id) == to_string(event_id)))
  end

  def find_event_document(events, nil, document_id) when is_list(events) do
    events
    |> cycle_documents_from_events()
    |> Enum.find(&(to_string(&1.id) == to_string(document_id)))
  end

  def find_event_document(events, event_id, document_id) when is_list(events) do
    case find_event(events, event_id) do
      nil -> nil
      event -> Enum.find(event.documents, &(to_string(&1.id) == to_string(document_id)))
    end
  end

  def event_uploadable?(event, assigns) do
    assigns[:live?] and assigns[:can_add_document?] and event.status in @uploadable_statuses
  end

  defp cycle_documents_from_events(events), do: Enum.flat_map(events, & &1.documents)

  def parse_slots(nil), do: []
  def parse_slots(""), do: []

  def parse_slots(csv) when is_binary(csv) do
    csv
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @doc """
  Narrows the completion modal to a single clicked slot when one is active,
  otherwise returns all required slots (the Done-flow / unscoped view). A stale
  active slot (no longer required) falls back to showing all slots.
  """
  def scoped_slots(slots, nil), do: slots

  def scoped_slots(slots, active) when is_binary(active) do
    if active in slots, do: [active], else: slots
  end

  @doc """
  Partitions cycle documents for the cycle-level required view.
  """
  def completion_view(documents, required_slots) do
    required = MapSet.new(required_slots)
    live = Enum.reject(documents, & &1.voided_at)

    slot_rows =
      Enum.map(required_slots, fn slot ->
        {slot, Enum.find(live, &(&1.document_slot == slot))}
      end)

    voided_required =
      documents
      |> Enum.filter(& &1.voided_at)
      |> Enum.filter(&(&1.document_slot in required))

    {slot_rows, voided_required}
  end

  @doc """
  Partitions one event's documents into live/voided "other" (supporting) files.
  """
  def step_files(event_documents, required_slots) do
    required = MapSet.new(required_slots)
    other? = fn doc -> is_nil(doc.document_slot) or doc.document_slot not in required end

    live_other = event_documents |> Enum.reject(& &1.voided_at) |> Enum.filter(other?)
    voided_other = event_documents |> Enum.filter(& &1.voided_at) |> Enum.filter(other?)

    {live_other, voided_other}
  end
end
