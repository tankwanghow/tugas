defmodule Argus.Accounts.User do
  use Argus.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :username, :string
    field :locale, :string, default: "en"
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    timestamps()
  end

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def locale_changeset(user, attrs) do
    user
    |> cast(attrs, [:locale])
    |> validate_required([:locale])
    |> validate_inclusion(:locale, ~w(en ms zh))
  end

  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :locale])
    |> validate_email(opts)
  end

  @doc """
  Changeset for a user changing their own username from settings. A blank value
  clears the username (allowed only while the user still has an email to log in
  with — a username-only user must keep one). A present username is validated
  for format, length, and uniqueness.
  """
  def username_changeset(user, attrs, opts \\ []) do
    user
    # empty_values: [] keeps "" so a deliberate clear registers as a change
    |> cast(attrs, [:username], empty_values: [])
    |> normalize_blank_username()
    |> validate_settings_username(user, opts)
  end

  defp normalize_blank_username(changeset) do
    case get_change(changeset, :username) do
      username when is_binary(username) ->
        if String.trim(username) == "",
          do: put_change(changeset, :username, nil),
          else: changeset

      _ ->
        changeset
    end
  end

  defp validate_settings_username(changeset, user, opts) do
    case get_field(changeset, :username) do
      nil ->
        if is_nil(user.email) do
          add_error(
            changeset,
            :username,
            "is required because you have no email to log in with"
          )
        else
          changeset
        end

      _username ->
        changeset = validate_username_rules(changeset)

        if Keyword.get(opts, :validate_unique, true) do
          changeset
          |> unsafe_validate_unique(:username, Argus.Repo)
          |> unique_constraint(:username)
        else
          changeset
        end
    end
  end

  defp validate_username_rules(changeset) do
    changeset
    |> validate_format(:username, ~r/^[a-zA-Z0-9_]+$/,
      message: "only letters, numbers, and underscores"
    )
    |> validate_length(:username, min: 3, max: 30)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_email_format()
      |> put_default_locale()

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Argus.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_format(changeset) do
    changeset
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
  end

  defp put_default_locale(changeset) do
    case get_field(changeset, :locale) do
      nil -> put_change(changeset, :locale, "en")
      _ -> changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  Registers an invited member from a username + password, with an optional
  email. Username is required (it's their login handle); email is optional.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:username, :email, :password, :locale])
    |> normalize_blank_email()
    |> validate_username(opts)
    |> maybe_validate_email(opts)
    |> validate_password(opts)
    |> put_default_locale()
  end

  # A blank email from an optional form field must be stored as NULL, not "",
  # otherwise two username-only users would collide on the unique email index.
  defp normalize_blank_email(changeset) do
    case get_change(changeset, :email) do
      email when is_binary(email) ->
        if String.trim(email) == "", do: delete_change(changeset, :email), else: changeset

      _ ->
        changeset
    end
  end

  defp validate_username(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:username])
      |> validate_format(:username, ~r/^[a-zA-Z0-9_]+$/,
        message: "only letters, numbers, and underscores"
      )
      |> validate_length(:username, min: 3, max: 30)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:username, Argus.Repo)
      |> unique_constraint(:username)
    else
      changeset
    end
  end

  defp maybe_validate_email(changeset, opts) do
    if get_field(changeset, :email) not in [nil, ""] do
      changeset = validate_email_format(changeset)

      if Keyword.get(opts, :validate_unique, true) do
        changeset |> unsafe_validate_unique(:email, Argus.Repo) |> unique_constraint(:email)
      else
        changeset
      end
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> validate_length(:password, max: 72, count: :bytes)
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Argus.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
