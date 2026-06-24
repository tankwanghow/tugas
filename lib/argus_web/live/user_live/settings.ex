defmodule ArgusWeb.UserLive.Settings do
  use ArgusWeb, :live_view

  on_mount {ArgusWeb.UserAuth, :require_sudo_mode}

  alias Argus.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_simple :if={@mobile?} flash={@flash} current_scope={@current_scope}>
      <.settings_body
        email_form={@email_form}
        password_form={@password_form}
        current_email={@current_email}
        trigger_submit={@trigger_submit}
        back_path={@back_path}
      />
    </Layouts.mobile_simple>

    <Layouts.app :if={not @mobile?} flash={@flash} current_scope={@current_scope}>
      <.settings_body
        email_form={@email_form}
        password_form={@password_form}
        current_email={@current_email}
        trigger_submit={@trigger_submit}
        back_path={@back_path}
      />
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)
    mobile? = ArgusWeb.Device.mobile_from_socket?(socket)

    socket =
      socket
      |> assign(:mobile?, mobile?)
      |> assign(:back_path, back_path(socket.assigns.current_scope, mobile?))
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  defp back_path(%{entity: %{slug: slug}}, true), do: ~p"/m/#{slug}"
  defp back_path(%{entity: %{slug: slug}}, false), do: ~p"/entities/#{slug}"
  defp back_path(_scope, _mobile?), do: ~p"/entities"

  attr :email_form, :any, required: true
  attr :password_form, :any, required: true
  attr :current_email, :string, required: true
  attr :trigger_submit, :boolean, required: true
  attr :back_path, :string, required: true

  defp settings_body(assigns) do
    ~H"""
    <div class="mx-auto max-w-lg space-y-6">
      <div>
        <.link
          navigate={@back_path}
          class="inline-flex items-center gap-1 text-sm text-base-content/60 hover:text-base-content"
        >
          <.icon name="hero-arrow-left-micro" class="size-4" /> Back
        </.link>
      </div>

      <div class="text-center">
        <.header>
          Account Settings
          <:subtitle>Manage your account email address and password settings</:subtitle>
        </.header>
      </div>

      <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
        <.input
          field={@email_form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          spellcheck="false"
          required
        />
        <.button variant="primary" phx-disable-with="Changing...">Change Email</.button>
      </.form>

      <div class="divider" />

      <.form
        for={@password_form}
        id="password_form"
        action={~p"/users/update-password"}
        method="post"
        phx-change="validate_password"
        phx-submit="update_password"
        phx-trigger-action={@trigger_submit}
      >
        <input
          name={@password_form[:email].name}
          type="hidden"
          id="hidden_user_email"
          spellcheck="false"
          value={@current_email}
        />
        <.input
          field={@password_form[:password]}
          type="password"
          label="New password"
          autocomplete="new-password"
          spellcheck="false"
          required
        />
        <.input
          field={@password_form[:password_confirmation]}
          type="password"
          label="Confirm new password"
          autocomplete="new-password"
          spellcheck="false"
        />
        <.button variant="primary" phx-disable-with="Saving...">
          Save Password
        </.button>
      </.form>
    </div>
    """
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end
end
