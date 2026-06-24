defmodule ArgusWeb.MobileAuthTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Argus.AccountsFixtures

  alias Argus.Accounts
  alias Argus.Entities.Membership
  alias Argus.Repo

  @mobile_ua "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"
  @standalone_shell_class "min-h-screen bg-base-200 flex flex-col items-center justify-center"

  defp assert_standalone_shell(html) do
    assert html =~ @standalone_shell_class
    refute html =~ ~s|id="argus-shell"|
    refute html =~ "Get started"
  end

  describe "unified auth UI" do
    test "register and log-in use mobile_standalone on desktop UA", %{conn: conn} do
      {:ok, _lv, register_html} = live(conn, ~p"/users/register")
      assert register_html =~ "Register"
      assert_standalone_shell(register_html)

      {:ok, view, login_html} = live(conn, ~p"/users/log-in")
      assert login_html =~ "Log in with email"
      assert_standalone_shell(login_html)
      assert has_element?(view, "#login_form_password")
    end

    test "register and log-in use mobile_standalone on mobile UA", %{conn: conn} do
      conn = put_req_header(conn, "user-agent", @mobile_ua)

      {:ok, _lv, html} = live(conn, ~p"/users/register")
      assert html =~ "Register"
      assert_standalone_shell(html)

      {:ok, view, html} = live(conn, ~p"/users/log-in")
      assert html =~ "Log in with email"
      assert_standalone_shell(html)
      assert has_element?(view, "#login_form_password")
    end

    test "registration creates account and navigates to log-in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      {:ok, _lv, html} =
        lv
        |> form("#registration_form", user: valid_user_attributes(email: email))
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "An email was sent"
    end

    test "desktop UA password login redirects to desktop dashboard", %{conn: conn} do
      scope = Argus.EntitiesFixtures.entity_scope_fixture()
      user = set_password(scope.user)

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form_password",
          user: %{identifier: user.email, password: valid_user_password(), remember_me: true}
        )

      conn = submit_form(form, conn)
      assert redirected_to(conn) == ~p"/entities/#{scope.entity.slug}"
    end

    test "mobile UA password login redirects to mobile dashboard", %{conn: conn} do
      scope = Argus.EntitiesFixtures.entity_scope_fixture()
      user = set_password(scope.user)
      conn = put_req_header(conn, "user-agent", @mobile_ua)

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form_password",
          user: %{identifier: user.email, password: valid_user_password(), remember_me: true}
        )

      conn = submit_form(form, conn)
      assert redirected_to(conn) == ~p"/m/#{scope.entity.slug}"
    end

    test "mobile UA full register then confirm lands on mobile dashboard when member", %{
      conn: conn
    } do
      admin_scope = Argus.EntitiesFixtures.entity_scope_fixture()
      conn = put_req_header(conn, "user-agent", @mobile_ua)

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      render_submit(form(lv, "#registration_form", user: valid_user_attributes(email: email)))

      user = Accounts.get_user_by_email(email)

      %Membership{
        user_id: user.id,
        entity_id: admin_scope.entity.id,
        role: "member",
        accepted_at: DateTime.utc_now(:second)
      }
      |> Membership.changeset(%{})
      |> Repo.insert!()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, confirm_lv, html} = live(conn, ~p"/users/log-in/#{token}")
      assert html =~ "Confirm and stay logged in"
      assert_standalone_shell(html)

      confirm_form = form(confirm_lv, "#confirmation_form", %{"user" => %{"token" => token}})
      render_submit(confirm_form)

      conn = follow_trigger_action(confirm_form, conn)
      assert redirected_to(conn) == ~p"/m/#{admin_scope.entity.slug}"
      assert Accounts.get_user!(user.id).confirmed_at
    end

    test "confirmation uses standalone shell", %{conn: conn} do
      user = unconfirmed_user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, _lv, html} = live(conn, ~p"/users/log-in/#{token}")
      assert html =~ "Confirm and stay logged in"
      assert html =~ "confirmation_form"
      assert_standalone_shell(html)
    end
  end
end
