defmodule ArgusWeb.MembershipLive.Index do
  use ArgusWeb, :live_view

  alias ArgusWeb.MembershipLive.IndexHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="members">
        <.header>
          Members
          <:subtitle>
            {@current_scope.entity.name} · {@seats_used}/{@current_scope.entity.seat_limit} seats
          </:subtitle>
        </.header>

        <section class="mt-6">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">Team</h2>
          <ul
            id="members-list"
            class="mt-3 divide-y divide-base-300 rounded-box border border-base-300"
          >
            <li
              :for={{user, membership} <- @members}
              id={"member-#{membership.id}"}
              class="flex items-center gap-3 p-3"
            >
              <div class="flex-1 min-w-0">
                <span :if={user.email} class="font-medium truncate">
                  {user.email}
                  <span :if={user.username} class="mx-4">♦</span>
                  <span :if={user.username} class="text-base-content/70 truncate">{user.username}</span>
                  <span :if={user.id == @current_scope.user.id} class="mx-4">♦</span>
                  <span :if={user.id == @current_scope.user.id} class="text-base-content/40">you</span>
                </span>
              </div>
              <form :if={@can_manage?} id={"role-form-#{membership.id}"} phx-change="change_role">
                <input type="hidden" name="membership_id" value={membership.id} />
                <select name="role" class="select select-sm w-36">
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

        <section :if={@can_manage?} class="mt-8">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
            Invite a member
          </h2>
          <.form
            for={@invite_form}
            id="invite-form"
            phx-submit="invite"
            class="mt-3 flex flex-wrap items-end gap-3"
          >
            <.input
              field={@invite_form[:email]}
              type="email"
              label="Email (optional)"
              class="input w-72"
            />
            <.input
              field={@invite_form[:role]}
              type="select"
              label="Role"
              options={IndexHelpers.roles()}
            />
            <.button class="btn btn-primary btn-sm" phx-disable-with="Inviting…">Send invite</.button>
          </.form>
          <div :if={@last_invite_link} class="alert alert-info mt-2" id="invite-link">
            <a href={@last_invite_link} target="_blank" rel="noopener" class="link break-all">
              {@last_invite_link}
            </a>
          </div>
          <div class="mt-4 flex gap-2">
            <.link
              navigate={~p"/entities/#{@current_scope.entity.slug}/invite-session/manager"}
              class="btn btn-outline btn-sm"
            >
              <.icon name="hero-qr-code" class="size-4" /> Manager QR
            </.link>
            <.link
              navigate={~p"/entities/#{@current_scope.entity.slug}/invite-session/member"}
              class="btn btn-outline btn-sm"
            >
              <.icon name="hero-qr-code" class="size-4" /> Member QR
            </.link>
          </div>
        </section>

        <section :if={@can_manage? and @pending != []} class="mt-8">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
            Pending invitations
          </h2>
          <ul
            id="pending-invitations"
            class="mt-3 divide-y divide-base-300 rounded-box border border-base-300"
          >
            <li
              :for={invite <- @pending}
              id={"invite-#{invite.id}"}
              class="flex items-center gap-3 p-3"
            >
              <div class="flex-1 min-w-0">
                <div class="font-medium truncate">{invite.email}</div>
                <div class="text-xs text-base-content/50">
                  {invite.role} · expires {format_zoned_date(
                    invite.expires_at,
                    @current_scope.entity.timezone
                  )}
                </div>
              </div>
              <span class="badge badge-warning badge-sm">pending</span>
              <button
                :if={@can_manage?}
                id={"revoke-invite-#{invite.id}"}
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
    </Layouts.app>
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
