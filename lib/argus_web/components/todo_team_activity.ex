defmodule ArgusWeb.TodoTeamActivity do
  @moduledoc """
  Entity-wide todo audit trail for the team log page.

  Rendered as a LiveView stream with a `phx-viewport-bottom` sentinel for infinite scroll.
  Each entry links to the matching todo on the index page (`?highlight=<todo_id>`), which
  briefly flashes that row (see the `TodoHighlight` hook). Entries whose todo has since been
  **deleted** can't be surfaced on the board, so they instead push `deleted_todo_notice` to
  flash a message in place (handled by the team-log LiveViews).
  """
  use Phoenix.Component

  alias ArgusWeb.TodoLive.ActivityFormat

  attr :id, :string, default: "todo-team-activity"
  attr :rows, :any, required: true, doc: "the @streams.activity stream"
  attr :empty?, :boolean, default: false
  attr :end?, :boolean, default: true
  attr :entity_slug, :string, required: true
  attr :variant, :atom, default: :desktop, values: [:desktop, :mobile]

  def todo_team_activity(assigns) do
    ~H"""
    <div id={@id}>
      <ul
        id={"#{@id}-list"}
        phx-update="stream"
        phx-viewport-bottom={!@end? && "load_more"}
        class="divide-y divide-base-300 rounded-box border border-base-300"
      >
        <li :for={{dom_id, log} <- @rows} id={dom_id} class="p-0">
          <button
            :if={deleted?(log)}
            type="button"
            phx-click="deleted_todo_notice"
            class="block w-full text-left p-3 text-sm hover:bg-base-200"
          >
            <.entry_body log={log} variant={@variant} deleted?={true} />
          </button>
          <.link
            :if={not deleted?(log)}
            navigate={todo_path(@variant, @entity_slug, log.todo_id)}
            class="block p-3 text-sm hover:bg-base-200"
          >
            <.entry_body log={log} variant={@variant} deleted?={false} />
          </.link>
        </li>
      </ul>
      <p :if={@empty?} id={"#{@id}-empty"} class="text-sm text-base-content/60">
        No team activity yet.
      </p>
    </div>
    """
  end

  attr :log, :map, required: true
  attr :variant, :atom, required: true
  attr :deleted?, :boolean, required: true

  defp entry_body(assigns) do
    ~H"""
    <%= if @variant == :desktop do %>
      <span class="font-medium">{ActivityFormat.audit_action_label(@log.action)}</span>
      {ActivityFormat.activity_subject(@log)} by {ActivityFormat.display_name(@log.user)}
      <span :if={@deleted?} class="text-base-content/40 italic">(deleted)</span>
      <span :if={@log.field} class="text-base-content/60">
        — {@log.field}: {@log.old_value || "—"} → {@log.new_value || "—"}
      </span>
      <span class="text-base-content/40">
        · {ActivityFormat.format_time(@log.inserted_at)}
      </span>
    <% else %>
      <div class="font-medium">
        {ActivityFormat.audit_action_label(@log.action)}
        <span :if={@deleted?} class="text-base-content/40 italic font-normal">(deleted)</span>
      </div>
      <div class="text-xs text-base-content/60 mt-0.5">
        {ActivityFormat.activity_subject(@log)}{ActivityFormat.display_name(@log.user)}
        <span class="text-base-content/40">
          · {ActivityFormat.format_time(@log.inserted_at)}
        </span>
      </div>
    <% end %>
    """
  end

  defp deleted?(%{todo: %{deleted_at: %DateTime{}}}), do: true
  defp deleted?(_), do: false

  defp todo_path(:mobile, slug, todo_id), do: "/m/#{slug}/todos?highlight=#{todo_id}"
  defp todo_path(_desktop, slug, todo_id), do: "/entities/#{slug}/todos?highlight=#{todo_id}"
end
