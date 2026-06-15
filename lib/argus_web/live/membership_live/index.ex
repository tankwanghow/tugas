defmodule ArgusWeb.MembershipLive.Index do
  use ArgusWeb, :live_view

  alias Argus.Authorization
  alias Argus.Entities

  @roles [{"Admin", "admin"}, {"Manager", "manager"}, {"Member", "member"}]

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
                <div class="font-medium truncate">{user.email}</div>
                <div :if={user.id == @current_scope.user.id} class="text-xs text-base-content/50">
                  you
                </div>
              </div>
              <form :if={@can_manage?} id={"role-form-#{membership.id}"} phx-change="change_role">
                <input type="hidden" name="membership_id" value={membership.id} />
                <select name="role" class="select select-sm w-36">
                  <option
                    :for={{label, value} <- roles()}
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
            <.input field={@invite_form[:role]} type="select" label="Role" options={roles()} />
            <.button class="btn btn-primary btn-sm" phx-disable-with="Inviting…">Send invite</.button>
          </.form>
          <div :if={@last_invite_link} class="alert alert-info mt-2" id="invite-link">
            <a href={@last_invite_link} target="_blank" rel="noopener" class="link break-all">
              {@last_invite_link}
            </a>
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
                  {invite.role} · expires {format_date(DateTime.to_date(invite.expires_at))}
                </div>
              </div>
              <span class="badge badge-warning badge-sm">pending</span>
              <button
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
    {:ok,
     socket
     |> assign(:can_manage?, Authorization.can?(socket.assigns.current_scope, :manage_entity))
     |> assign(:invite_form, to_form(%{"email" => "", "role" => "member"}, as: :invite))
     |> assign(:last_invite_link, nil)
     |> load_members()}
  end

  @impl true
  def handle_event("change_role", %{"membership_id" => id, "role" => role}, socket) do
    scope = socket.assigns.current_scope
    membership = Entities.get_membership_in_entity!(scope.entity, id)

    case Entities.update_member_role(scope, membership, role) do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, "Role updated.") |> assign(:last_invite_link, nil) |> load_members()}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update role.")}
    end
  end

  def handle_event("revoke_invitation", %{"invitation_id" => invitation_id}, socket) do
    scope = socket.assigns.current_scope

    case Entities.revoke_invitation(scope, invitation_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invitation revoked.")
         |> assign(:last_invite_link, nil)
         |> load_members()}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Invitation not found.")}
    end
  end

  def handle_event("invite", %{"invite" => %{"email" => email, "role" => role}}, socket) do
    scope = socket.assigns.current_scope

    url_fun = fn encoded -> url(~p"/invitations/#{encoded}") end

    case Entities.invite_member(scope, email, role, url_fun) do
      {:ok, invitation} ->
        link = url(~p"/invitations/#{Argus.Entities.Invitation.encode_token(invitation.token)}")

        {:noreply,
         socket
         |> put_flash(:info, invite_flash(invitation))
         |> assign(:invite_form, to_form(%{"email" => "", "role" => "member"}, as: :invite))
         |> assign(:last_invite_link, link)
         |> load_members()}

      {:error, :seat_limit_reached} ->
        {:noreply, put_flash(socket, :error, "Seat limit reached — no seats available.")}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "Check the email address and try again.")}
    end
  end

  defp invite_flash(%{email: nil}), do: "Invitation created. Share the link below."
  defp invite_flash(%{email: email}), do: "Invitation sent to #{email}."

  defp load_members(socket) do
    entity = socket.assigns.current_scope.entity
    members = Entities.list_entity_members(entity)

    socket
    |> assign(:members, members)
    |> assign(:seats_used, length(members))
    |> assign(:pending, Entities.list_pending_invitations(entity))
  end

  defp roles, do: @roles
end
