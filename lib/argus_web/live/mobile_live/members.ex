defmodule ArgusWeb.MobileLive.Members do
  use ArgusWeb, :live_view

  alias ArgusWeb.MembershipLive.IndexHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} active={:more}>
      <div id="m-members" class="p-4 space-y-6">
        <div>
          <h1 class="font-semibold text-xl">Members</h1>
          <p class="text-sm text-base-content/60 mt-1">
            {@current_scope.entity.name} · {@seats_used}/{@current_scope.entity.seat_limit} seats
          </p>
        </div>

        <section>
          <h2 class="text-xs font-semibold uppercase tracking-wide text-base-content/60">Team</h2>
          <ul
            id="m-members-list"
            class="mt-2 divide-y divide-base-300 rounded-box border border-base-300"
          >
            <li
              :for={{user, membership} <- @members}
              id={"m-member-#{membership.id}"}
              class="flex flex-col gap-2 p-3 sm:flex-row sm:items-center"
            >
              <div class="flex-1 min-w-0">
                <div class="font-medium truncate">{user.email}</div>
                <div :if={user.username} class="text-sm text-base-content/60 truncate">
                  {user.username}
                </div>
              </div>
              <form
                :if={@can_manage?}
                id={"m-role-form-#{membership.id}"}
                phx-change="change_role"
                class="shrink-0"
              >
                <input type="hidden" name="membership_id" value={membership.id} />
                <select name="role" class="select select-sm w-full sm:w-36">
                  <option
                    :for={{label, value} <- IndexHelpers.roles()}
                    value={value}
                    selected={membership.role == value}
                  >
                    {label}
                  </option>
                </select>
              </form>
              <span :if={not @can_manage?} class="badge badge-ghost badge-sm capitalize">
                {membership.role}
              </span>
            </li>
          </ul>
        </section>

        <section :if={@can_manage?}>
          <h2 class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
            Invite a member
          </h2>
          <.form
            for={@invite_form}
            id="m-invite-form"
            phx-submit="invite"
            class="mt-2 space-y-3"
          >
            <.input field={@invite_form[:email]} type="email" label="Email (optional)" />
            <.input
              field={@invite_form[:role]}
              type="select"
              label="Role"
              options={IndexHelpers.roles()}
            />
            <.button class="btn btn-primary btn-sm w-full" phx-disable-with="Inviting…">
              Send invite
            </.button>
          </.form>
          <div :if={@last_invite_link} class="alert alert-info mt-2" id="m-invite-link">
            <a href={@last_invite_link} target="_blank" rel="noopener" class="link break-all">
              {@last_invite_link}
            </a>
          </div>
        </section>

        <section :if={@pending != []}>
          <h2 class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
            Pending invites
          </h2>
          <ul
            id="m-pending-invites"
            class="mt-2 divide-y divide-base-300 rounded-box border border-base-300"
          >
            <li
              :for={invite <- @pending}
              id={"m-pending-invite-#{invite.id}"}
              class="flex items-center gap-2 p-3"
            >
              <div class="flex-1 min-w-0">
                <div class="font-medium truncate">{invite.email || "Link invite"}</div>
                <div class="text-xs text-base-content/50">
                  {invite.role} · expires {format_zoned_date(
                    invite.expires_at,
                    @current_scope.entity.timezone
                  )}
                </div>
              </div>
              <span :if={@can_manage?} class="badge badge-warning badge-sm">pending</span>
              <button
                :if={@can_manage?}
                id={"m-revoke-invite-#{invite.id}"}
                type="button"
                phx-click="revoke_invitation"
                phx-value-invitation_id={invite.id}
                class="btn btn-ghost btn-xs text-error"
              >
                Revoke
              </button>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.mobile_app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, IndexHelpers.mount_assigns(socket)}
  end

  @impl true
  def handle_event("change_role", params, socket) do
    IndexHelpers.handle_change_role(socket, params) |> IndexHelpers.handle_result()
  end

  def handle_event("revoke_invitation", params, socket) do
    IndexHelpers.handle_revoke_invitation(socket, params) |> IndexHelpers.handle_result()
  end

  def handle_event("invite", params, socket) do
    IndexHelpers.handle_invite(socket, params) |> IndexHelpers.handle_result()
  end

  def handle_event("close_modal_on_escape", _params, socket), do: {:noreply, socket}
end
