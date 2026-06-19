defmodule ArgusWeb.MobileLiveTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Argus.ObligationsFixtures

  alias Argus.Obligations

  @mobile_ua "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"

  setup :register_and_log_in_user

  defp mobile_conn(conn, scope) do
    conn |> log_in_user(scope.user) |> put_req_header("user-agent", @mobile_ua)
  end

  test "mobile dashboard renders live cycles", %{conn: conn} do
    {scope, obligation} = assigned_member_scope_fixture()
    conn = mobile_conn(conn, scope)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}")

    assert has_element?(view, "#mobile-obligations")
    assert has_element?(view, "#m-ob-#{obligation.id}")
  end

  test "mobile show runs start_progress workflow", %{conn: conn} do
    {scope, obligation} = assigned_member_scope_fixture()
    conn = mobile_conn(conn, scope)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#m-start-progress-btn") |> render_click()
    assert has_element?(view, "#m-progress-modal")

    view
    |> form("#m-progress-form", %{"progress" => %{"note" => "On it"}})
    |> render_submit()

    assert render(view) =~ "in_progress"
  end

  test "mobile recurring obligation shows skip instead of cancel", %{conn: conn} do
    {scope, obligation} = recurring_manager_scope_fixture(interval: "monthly")
    conn = mobile_conn(conn, scope)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}/obligations/#{obligation.id}")

    refute has_element?(view, "#m-cancel-btn")
    assert has_element?(view, "#m-skip-btn")
  end

  test "mobile escape closes open modals", %{conn: conn} do
    {scope, obligation} = manager_obligation_scope_fixture()
    conn = mobile_conn(conn, scope)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#m-done-btn") |> render_click()
    assert has_element?(view, "#m-done-modal")

    view |> element("#argus-shell") |> render_keydown()
    refute has_element?(view, "#m-done-modal")
  end

  test "mobile completed badge shows the completion datetime", %{conn: conn} do
    {scope, obligation} = manager_obligation_scope_fixture()
    conn = mobile_conn(conn, scope)

    {:ok, done, _} = Obligations.complete(scope, obligation, %{note: "Done"})
    stamp = ArgusWeb.CoreComponents.format_datetime(done.completed_at)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}/obligations/#{done.id}")

    assert render(view) =~ "Completed"
    assert render(view) =~ stamp
  end

  test "mobile note editing happens in a modal", %{conn: conn} do
    {scope, obligation} = manager_obligation_scope_fixture()
    conn = mobile_conn(conn, scope)
    event = hd(Argus.Obligations.list_events(obligation))

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}/obligations/#{obligation.id}")

    refute has_element?(view, "#m-note-modal")
    view |> element("#m-edit-note-#{event.id}") |> render_click()
    assert has_element?(view, "#m-note-modal")

    view |> form("#m-note-form", %{"note" => %{"note" => "Edited via modal"}}) |> render_submit()

    refute has_element?(view, "#m-note-modal")
    assert render(view) =~ "Edited via modal"
  end

  test "mobile cancel modal requires a reason", %{conn: conn} do
    {scope, obligation} = manager_obligation_scope_fixture()
    conn = mobile_conn(conn, scope)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#m-cancel-btn") |> render_click()
    assert has_element?(view, "#m-cancel-modal")

    view |> form("#m-cancel-form", %{"cancel" => %{"note" => ""}}) |> render_submit()
    assert render(view) =~ "A reason is required"
  end

  test "mobile done modal requires next due for recurring", %{conn: conn} do
    {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")
    conn = mobile_conn(conn, scope)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#m-done-btn") |> render_click()

    view
    |> form("#m-done-form", %{"done" => %{"next_due_by" => "", "note" => "Done"}})
    |> render_submit()

    assert render(view) =~ "Next due date is required"
  end

  test "completing on mobile spawns successor and redirects to list", %{conn: conn} do
    {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")
    conn = mobile_conn(conn, scope)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#m-done-btn") |> render_click()

    view
    |> form("#m-done-form", %{"done" => %{"next_due_by" => "2026-07-15", "note" => "Done"}})
    |> render_submit()

    assert_redirect(view, ~p"/m/#{scope.entity.slug}/obligations")
    refute Obligations.get_obligation!(scope, obligation.id).completed_at == nil
  end

  test "mobile obligations list filters completed cycles", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    member_scope = member_scope_on_entity(manager.entity)
    conn = mobile_conn(conn, member_scope)
    type = type_fixture(manager.entity)

    {:ok, _} =
      Obligations.create_obligation(manager, %{
        title: "Alpha Live",
        obligation_type_id: type.id,
        primary_assignee_id: member_scope.user.id,
        due_by: ~D[2026-06-30],
        open_note: "Alpha"
      })

    {:ok, to_complete} =
      Obligations.create_obligation(manager, %{
        title: "Beta Done",
        obligation_type_id: type.id,
        primary_assignee_id: member_scope.user.id,
        due_by: ~D[2026-05-30],
        open_note: "Beta"
      })

    assert {:ok, completed, _} =
             Obligations.complete(member_scope, to_complete, %{note: "Done"})

    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}/obligations")

    view |> element("#m-filter-my_completed") |> render_click()
    assert has_element?(view, "#m-ob-#{completed.id}")
    refute has_element?(view, "#m-obligations-empty")
  end

  test "mobile more sheet links to all entities picker", %{conn: conn} do
    {scope, _} = assigned_member_scope_fixture()
    conn = mobile_conn(conn, scope)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}")

    assert has_element?(view, "a[href='/entities?pick=1']", "Switch entity")
  end

  test "mobile UA is redirected from desktop dashboard to /m", %{conn: conn} do
    {scope, _obligation} = assigned_member_scope_fixture()

    conn =
      conn
      |> log_in_user(scope.user)
      |> put_req_header("user-agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)")
      |> get(~p"/entities/#{scope.entity.slug}")

    assert redirected_to(conn) == ~p"/m/#{scope.entity.slug}"
  end

  test "mobile: manager marks a completed cycle in error", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)
    type = type_fixture(manager.entity)

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "EPF Jan",
        obligation_type_id: type.id,
        primary_assignee_id: manager.user.id,
        due_by: ~D[2026-06-15],
        open_note: "open"
      })

    {:ok, done, _} = Obligations.complete(manager, obligation, %{note: "Done"})

    {:ok, view, _html} =
      live(conn, ~p"/m/#{manager.entity.slug}/obligations/#{done.id}")

    assert has_element?(view, "#m-mark-error-btn")

    view |> element("#m-mark-error-btn") |> render_click()
    assert has_element?(view, "#m-correct-modal")

    view
    |> form("#m-correct-form", %{"correct" => %{"reason" => "Wrong figures"}})
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    assert path =~ "/m/#{manager.entity.slug}/obligations/"
    refute path =~ done.id

    {:ok, replacement_view, _} = live(conn, path)
    assert has_element?(replacement_view, "#m-replaces-banner")
  end

  test "mobile completion modal uploads into a slot", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "EPF",
        obligation_type_id: type.id,
        due_by: ~D[2026-06-30],
        open_note: "open"
      })

    {:ok, view, _html} =
      live(conn, ~p"/m/#{manager.entity.slug}/obligations/#{obligation.id}")

    view |> element("#m-open-completion-slot-receipt") |> render_click()
    view |> element("#m-select-slot-receipt") |> render_click()

    file =
      file_input(view, "#m-completion-upload-form", :document, [
        %{name: "receipt.pdf", content: "x", type: "application/pdf"}
      ])

    render_upload(file, "receipt.pdf")
    view |> form("#m-completion-upload-form", %{"picker_slot" => "receipt"}) |> render_change()
    view |> element("#m-upload-slot-receipt") |> render_click()

    assert has_element?(view, "#m-completion-slot-receipt", "receipt.pdf")
  end

  test "mobile: obligations index shows the New entry point for a manager", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)

    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}/obligations")

    assert has_element?(
             view,
             "#m-new-obligation-btn[href='/m/#{manager.entity.slug}/obligations/new']"
           )
  end

  test "mobile: new-obligation form creates and redirects to the mobile show page", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)
    type = type_fixture(manager.entity)

    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}/obligations/new")

    assert has_element?(view, "#m-obligation-form", "New obligation")

    # The mobile shell binds a global Escape keydown; the form must not crash on it.
    assert view |> element("#argus-shell") |> render_keydown() =~ "New obligation"

    view
    |> form("#m-obligation-create-form", %{
      "obligation" => %{
        "title" => "Mobile EPF",
        "obligation_type_id" => type.id,
        "due_by" => "2026-06-30",
        "open_note" => "Created on mobile"
      }
    })
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    assert path =~ "/m/#{manager.entity.slug}/obligations/"
    refute path =~ "/new"

    [created] = Argus.Obligations.list_team_overview(manager)
    assert created.title == "Mobile EPF"
  end
end
