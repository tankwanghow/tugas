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
              :for={{user, membership, counts} <- @members}
              id={"m-member-#{membership.id}"}
              class={[
                "flex flex-col gap-2 p-3 sm:flex-row sm:items-center",
                membership.disabled_at && "opacity-60"
              ]}
            >
              <div class="flex flex-wrap items-center gap-2 min-w-0">
                <div class="font-medium truncate">
                  {user_label(user)}
                  <span :if={membership.disabled_at} class="badge badge-ghost badge-sm ml-1">
                    disabled
                  </span>
                </div>
                <div :if={user.username && user.email} class="text-sm text-base-content/60 truncate">
                  {user.email}
                </div>
                <div
                  :if={is_nil(membership.disabled_at) and IndexHelpers.assignment_total(counts) > 0}
                  class="text-xs text-base-content/50"
                >
                  {IndexHelpers.assignment_summary(counts)}
                </div>
              </div>
              <div class="flex justify-between items-center gap-2">
                <form
                  :if={@can_manage? and is_nil(membership.disabled_at)}
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
                <span
                  :if={not @can_manage? or membership.disabled_at}
                  class="badge badge-ghost badge-sm capitalize"
                >
                  {membership.role}
                </span>
                <button
                  :if={
                    @can_manage? and is_nil(membership.disabled_at) and
                      user.id != @current_scope.user.id
                  }
                  id={"m-disable-member-#{membership.id}"}
                  type="button"
                  phx-click="request_disable"
                  phx-value-membership_id={membership.id}
                  class="btn btn-ghost btn-xs text-error"
                >
                  Disable
                </button>
                <button
                  :if={@can_manage? and membership.disabled_at}
                  id={"m-enable-member-#{membership.id}"}
                  type="button"
                  phx-click="enable_member"
                  phx-value-membership_id={membership.id}
                  class="btn btn-ghost btn-xs text-success"
                >
                  Enable
                </button>
              </div>
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

        <div :if={@disabling} id="m-disable-member-modal" class="modal modal-open">
          <div class="modal-box">
            <h3 class="text-lg font-semibold">Disable {user_label(@disabling.user)}?</h3>
            <p class="mt-2 text-sm text-base-content/70">
              They lose access to {@current_scope.entity.name} and stop using a seat. You can re-enable them later.
            </p>
            <ul class="mt-3 list-inside list-disc text-sm text-base-content/80">
              <li>{IndexHelpers.assignment_summary(@disabling.counts)} will be cleared</li>
              <li>their live duties become unassigned for a manager to reassign</li>
            </ul>
            <div class="modal-action">
              <button type="button" phx-click="cancel_disable" class="btn btn-ghost btn-sm">
                Cancel
              </button>
              <button
                type="button"
                id="m-confirm-disable"
                phx-click="confirm_disable"
                class="btn btn-error btn-sm"
              >
                Disable
              </button>
            </div>
          </div>
        </div>
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

  def handle_event("request_disable", params, socket) do
    IndexHelpers.handle_request_disable(socket, params)
  end

  def handle_event("confirm_disable", _params, socket) do
    IndexHelpers.handle_confirm_disable(socket)
  end

  def handle_event("cancel_disable", _params, socket) do
    {:noreply, IndexHelpers.close_disable_modal(socket)}
  end

  def handle_event("enable_member", params, socket) do
    IndexHelpers.handle_enable_member(socket, params)
  end

  def handle_event("close_modal_on_escape", _params, socket) do
    {:noreply, IndexHelpers.close_disable_modal(socket)}
  end
end
