defmodule ArgusWeb.MobileLiveTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Argus.ObligationsFixtures
  import Argus.UploadFixtures

  alias Argus.Obligations

  @mobile_ua "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"

  setup :register_and_log_in_user

  defp mobile_conn(conn, scope) do
    conn |> log_in_user(scope.user) |> put_req_header("user-agent", @mobile_ua)
  end

  test "mobile dashboard restores filters saved in the session", %{conn: conn} do
    {scope, _} = manager_obligation_scope_fixture()

    conn =
      conn
      |> mobile_conn(scope)
      |> init_test_session(%{})
      |> Plug.Conn.put_session(:dashboard_filters, %{
        scope.entity.slug => %{
          "mine" => "true",
          "lifecycle" => "skipped",
          "query" => "audit"
        }
      })

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}")

    assert has_element?(view, "#m-scope-mine.tab-active")
    assert has_element?(view, "#m-obligation-search[value='audit']")

    html = render(view)
    assert html =~ ~s(value="skipped" selected)
  end

  test "mobile dashboard renders live cycles", %{conn: conn} do
    {scope, obligation} = assigned_member_scope_fixture()
    conn = mobile_conn(conn, scope)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}")

    assert has_element?(view, "#mobile-obligations")
    assert has_element?(view, "#m-ob-#{obligation.id}")
  end

  test "mobile dashboard card shows the current event", %{conn: conn} do
    {scope, obligation} = manager_obligation_scope_fixture()
    conn = mobile_conn(conn, scope)

    assert {:ok, _} = Obligations.start_progress(scope, obligation, %{note: "On it"})

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}")

    assert has_element?(
             view,
             "#m-ob-#{obligation.id}[data-event-count='2'][data-event-status='in_progress']",
             "In progress"
           )

    assert has_element?(view, "#m-ob-#{obligation.id}", "On it")
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

  test "mobile skip button shown for all live cycles (recurring and one-off)", %{conn: conn} do
    {scope, obligation} = recurring_manager_scope_fixture(interval: "monthly")
    conn = mobile_conn(conn, scope)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}/obligations/#{obligation.id}")

    refute has_element?(view, "#m-cancel-btn")
    assert has_element?(view, "#m-skip-btn")

    {scope2, obligation2} = manager_obligation_scope_fixture()
    conn2 = mobile_conn(build_conn(), scope2)

    {:ok, view2, _html} = live(conn2, ~p"/m/#{scope2.entity.slug}/obligations/#{obligation2.id}")

    refute has_element?(view2, "#m-cancel-btn")
    assert has_element?(view2, "#m-skip-btn")
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

  test "mobile skip modal closes a one-off cycle", %{conn: conn} do
    {scope, obligation} = manager_obligation_scope_fixture()
    conn = mobile_conn(conn, scope)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#m-skip-btn") |> render_click()
    assert has_element?(view, "#m-skip-modal")

    view |> form("#m-skip-form", %{"skip" => %{"note" => "Not needed"}}) |> render_submit()

    assert_redirect(view, ~p"/m/#{scope.entity.slug}")
    assert Obligations.get_obligation!(scope, obligation.id).closed_at
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

  test "completing on mobile spawns successor and redirects to dashboard", %{conn: conn} do
    {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")
    conn = mobile_conn(conn, scope)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#m-done-btn") |> render_click()

    view
    |> form("#m-done-form", %{"done" => %{"next_due_by" => "2026-07-15", "note" => "Done"}})
    |> render_submit()

    assert_redirect(view, ~p"/m/#{scope.entity.slug}")
    refute Obligations.get_obligation!(scope, obligation.id).completed_at == nil
  end

  test "mobile dashboard filters completed cycles", %{conn: conn} do
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

    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}")

    # member defaults to Mine; switch the status dropdown to Completed
    view |> form("#m-obligation-status-filter", %{lifecycle: "completed"}) |> render_change()
    assert has_element?(view, "#m-ob-#{completed.id}")
    refute has_element?(view, "#m-obligations-empty")
  end

  test "mobile dashboard filters skipped cycles", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)
    type = type_fixture(manager.entity)

    {:ok, to_skip} =
      Obligations.create_obligation(manager, %{
        title: "Skip Me",
        obligation_type_id: type.id,
        due_by: ~D[2026-06-30],
        open_note: "Opening"
      })

    assert {:ok, skipped, nil} = Obligations.skip(manager, to_skip, %{note: "Skipping it"})

    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}")

    view |> form("#m-obligation-status-filter", %{lifecycle: "skipped"}) |> render_change()
    assert has_element?(view, "#m-ob-#{skipped.id}")
    assert render(view) =~ "skipped"
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

    # Attach the receipt (as the UploadDirect/controller path would), then the
    # client signals the LiveView to refresh.
    seed_document(manager, obligation, "receipt", "receipt.pdf")
    view |> element("#mobile-obligation-show") |> render_hook("document_uploaded", %{})

    assert has_element?(
             view,
             "#m-summary-slot-receipt a[data-doc-kind='pdf'][data-doc-name='receipt.pdf']"
           )
  end

  test "mobile completion slot offers a direct-upload Choose file button", %{conn: conn} do
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

    assert has_element?(
             view,
             "#m-select-slot-receipt[phx-hook='UploadDirect']" <>
               "[data-upload-url='/entities/#{manager.entity.slug}/obligations/#{obligation.id}/documents']"
           )
  end

  test "mobile show: completion summary and timeline render document thumb tiles", %{
    conn: conn
  } do
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

    assert has_element?(view, "#m-completion-summary.w-full")
    assert has_element?(view, "#m-open-completion-slot-receipt")

    obligation = Obligations.get_obligation!(manager, obligation.id)
    [open_event] = Enum.filter(obligation.events, &(&1.status == "open"))

    {:ok, _receipt} =
      Obligations.add_document(
        manager,
        obligation,
        open_event,
        upload_fixture("receipt.pdf"),
        "receipt"
      )

    {:ok, notes} =
      Obligations.add_document(
        manager,
        obligation,
        open_event,
        upload_fixture("notes.jpg"),
        nil
      )

    {:ok, view, _html} =
      live(conn, ~p"/m/#{manager.entity.slug}/obligations/#{obligation.id}")

    assert has_element?(
             view,
             "#m-summary-slot-receipt a[data-doc-kind='pdf'][data-doc-name='receipt.pdf']"
           )

    assert has_element?(view, "#m-event-files-#{open_event.id}.w-full")
    refute has_element?(view, "#m-event-files-#{open_event.id}", "receipt.pdf")

    assert has_element?(
             view,
             "#m-event-file-#{notes.id} a[data-doc-kind='image'][data-doc-name='notes.jpg'] img"
           )
  end

  test "mobile: bottom nav shows the New entry point for a manager", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)

    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}")

    assert has_element?(
             view,
             "#m-new-obligation-btn[href='/m/#{manager.entity.slug}/obligations/new']"
           )
  end

  test "mobile sort dropdown reorders and infinite scroll appends", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)
    type = type_fixture(manager.entity)

    for i <- 1..30 do
      {:ok, _} =
        Argus.Obligations.create_obligation(manager, %{
          title: "Duty #{String.pad_leading(Integer.to_string(i), 2, "0")}",
          obligation_type_id: type.id,
          due_by: Date.add(~D[2026-06-01], i),
          open_note: "n"
        })
    end

    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}")

    assert view |> element("#mobile-obligations") |> render() =~ "Duty 25"
    refute view |> element("#mobile-obligations") |> render() =~ "Duty 26"

    render_hook(view, "load_more", %{})
    assert view |> element("#mobile-obligations") |> render() =~ "Duty 26"

    assert has_element?(view, "#m-obligation-sort option[value='urgency']")
  end

  test "mobile Someday lifecycle lists dateless duties without urgency/due chrome", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)
    type = type_fixture(manager.entity)

    {:ok, _} =
      Obligations.create_obligation(manager, %{
        title: "Tidy the archive",
        obligation_type_id: type.id,
        someday: true,
        open_note: "n"
      })

    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}")
    view |> form("#m-obligation-status-filter", %{lifecycle: "someday"}) |> render_change()

    html = view |> element("#mobile-obligations") |> render()
    assert html =~ "Tidy the archive"
    refute html =~ "overdue"
    refute html =~ "due "
  end

  test "mobile: new-obligation form creates and redirects to the mobile show page", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, manager)
    type = type_fixture(manager.entity)

    {:ok, view, _html} = live(conn, ~p"/m/#{manager.entity.slug}/obligations/new")

    assert has_element?(view, "#m-obligation-form", "New duty")

    # The mobile shell binds a global Escape keydown; the form must not crash on it.
    assert view |> element("#argus-shell") |> render_keydown() =~ "New duty"

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
