defmodule ArgusWeb.TodoTeamActivity do
  @moduledoc """
  Entity-wide todo audit trail for the team log page.
  """
  use Phoenix.Component

  alias ArgusWeb.TodoLive.ActivityFormat

  attr :logs, :list, required: true
  attr :id, :string, default: "todo-team-activity"
  attr :variant, :atom, default: :desktop, values: [:desktop, :mobile]

  def todo_team_activity(assigns) do
    ~H"""
    <div id={@id}>
      <ul
        :if={@logs != []}
        class={[
          @variant == :desktop && "divide-y divide-base-300 rounded-box border border-base-300",
          @variant == :mobile && "divide-y divide-base-300 rounded-box border border-base-300"
        ]}
      >
        <li :for={log <- @logs} id={"#{@id}-entry-#{log.id}"} class="p-3 text-sm">
          <%= if @variant == :desktop do %>
            <span class="font-medium">{ActivityFormat.audit_action_label(log.action)}</span>
            {ActivityFormat.activity_subject(log)} by {ActivityFormat.display_name(log.user)}
            <span :if={log.field} class="text-base-content/60">
              — {log.field}: {log.old_value || "—"} → {log.new_value || "—"}
            </span>
            <span class="text-base-content/40"> · {ActivityFormat.format_time(log.inserted_at)}</span>
          <% else %>
            <div class="font-medium">{ActivityFormat.audit_action_label(log.action)}</div>
            <div class="text-xs text-base-content/60 mt-0.5">
              {ActivityFormat.activity_subject(log)}{ActivityFormat.display_name(log.user)}
              <span class="text-base-content/40">
                · {ActivityFormat.format_time(log.inserted_at)}
              </span>
            </div>
          <% end %>
        </li>
      </ul>
      <p :if={@logs == []} id={"#{@id}-empty"} class="text-sm text-base-content/60">
        No team activity yet.
      </p>
    </div>
    """
  end
end
