defmodule ArgusWeb.MembershipLive.IndexHelpers do
  @moduledoc false

  use ArgusWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Argus.Authorization
  alias Argus.Entities

  @roles [{"Admin", "admin"}, {"Manager", "manager"}, {"Member", "member"}]

  def roles, do: @roles

  def mount_assigns(socket) do
    socket
    |> assign(:can_manage?, Authorization.can?(socket.assigns.current_scope, :manage_entity))
    |> assign(:invite_form, to_form(%{"email" => "", "role" => "member"}, as: :invite))
    |> assign(:last_invite_link, nil)
    |> load_members()
  end

  def handle_change_role(socket, %{"membership_id" => id, "role" => role}) do
    scope = socket.assigns.current_scope
    membership = Entities.get_membership_in_entity!(scope.entity, id)

    case Entities.update_member_role(scope, membership, role) do
      {:ok, _} ->
        {:ok,
         socket
         |> put_flash(:info, "Role updated.")
         |> assign(:last_invite_link, nil)
         |> load_members()}

      :not_authorise ->
        {:error, put_flash(socket, :error, "Not authorized.")}

      {:error, _} ->
        {:error, put_flash(socket, :error, "Could not update role.")}
    end
  end

  def handle_revoke_invitation(socket, %{"invitation_id" => invitation_id}) do
    scope = socket.assigns.current_scope

    case Entities.revoke_invitation(scope, invitation_id) do
      {:ok, _} ->
        {:ok,
         socket
         |> put_flash(:info, "Invitation revoked.")
         |> assign(:last_invite_link, nil)
         |> load_members()}

      :not_authorise ->
        {:error, put_flash(socket, :error, "Not authorized.")}

      {:error, :not_found} ->
        {:error, put_flash(socket, :error, "Invitation not found.")}
    end
  end

  def handle_invite(socket, %{"invite" => %{"email" => email, "role" => role}}) do
    scope = socket.assigns.current_scope
    url_fun = fn encoded -> url(~p"/invitations/#{encoded}") end

    case Entities.invite_member(scope, email, role, url_fun) do
      {:ok, invitation} ->
        link = url(~p"/invitations/#{Entities.Invitation.encode_token(invitation.token)}")

        {:ok,
         socket
         |> put_flash(:info, invite_flash(invitation))
         |> assign(:invite_form, to_form(%{"email" => "", "role" => "member"}, as: :invite))
         |> assign(:last_invite_link, link)
         |> load_members()}

      {:error, :seat_limit_reached} ->
        {:error, put_flash(socket, :error, "Seat limit reached — no seats available.")}

      :not_authorise ->
        {:error, put_flash(socket, :error, "Not authorized.")}

      {:error, %Ecto.Changeset{}} ->
        {:error, put_flash(socket, :error, "Check the email address and try again.")}
    end
  end

  def handle_result({:ok, socket}), do: {:noreply, socket}
  def handle_result({:error, socket}), do: {:noreply, socket}

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
end
