defmodule TugasWeb.DutyLiveTest do
  use TugasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tugas.DutiesFixtures
  import Tugas.UploadFixtures

  alias Tugas.Duties

  setup :register_and_log_in_user

  test "dashboard filters completed and skipped cycles", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    member_scope = member_scope_on_entity(manager.entity)
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)

    {:ok, live_duty} =
      Duties.create_duty(manager, %{
        title: "Alpha Live",
        duty_type_id: type.id,
        primary_assignee_id: member_scope.user.id,
        due_by: ~D[2026-06-30],
        open_note: "Alpha"
      })

    {:ok, to_complete} =
      Duties.create_duty(manager, %{
        title: "Beta Done",
        duty_type_id: type.id,
        primary_assignee_id: member_scope.user.id,
        due_by: ~D[2026-05-30],
        open_note: "Beta"
      })

    assert {:ok, completed, _} =
             Duties.complete(member_scope, to_complete, %{note: "Done"})

    {:ok, to_skip} =
      Duties.create_duty(manager, %{
        title: "Gamma Skipped",
        duty_type_id: type.id,
        primary_assignee_id: member_scope.user.id,
        due_by: ~D[2026-04-30],
        open_note: "Gamma"
      })

    assert {:ok, _skipped, nil} =
             Duties.skip(manager, to_skip, %{note: "No longer needed"})

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}/duties")

    assert has_element?(view, "#duty-row-#{live_duty.id}")
    refute has_element?(view, "#duty-row-#{completed.id}")

    view |> form("#duty-status-filter", %{lifecycle: "completed"}) |> render_change()
    assert has_element?(view, "#duty-row-#{completed.id}")
    refute has_element?(view, "#duty-row-#{live_duty.id}")

    view |> form("#duty-status-filter", %{lifecycle: "skipped"}) |> render_change()
    assert has_element?(view, "#duty-row-#{to_skip.id}")

    member_conn = log_in_user(conn, member_scope.user)

    {:ok, member_view, _html} =
      live(member_conn, ~p"/entities/#{manager.entity.slug}/duties")

    # member defaults to Mine + Live
    assert has_element?(member_view, "#scope-mine.tab-active")
    assert has_element?(member_view, "#duty-row-#{live_duty.id}")

    member_view |> form("#duty-status-filter", %{lifecycle: "completed"}) |> render_change()
    assert has_element?(member_view, "#duty-row-#{completed.id}")

    view |> form("#duty-status-filter", %{lifecycle: "live"}) |> render_change()
    view |> element("#duty-search") |> render_keyup(%{"value" => "Alpha"})
    assert has_element?(view, "#duty-row-#{live_duty.id}")
    refute has_element?(view, "#duty-row-#{to_skip.id}")
  end

  test "manager creates duty via form", %{conn: conn} do
    {scope, _} = manager_duty_scope_fixture()
    conn = log_in_user(conn, scope.user)
    assignee = member_fixture(scope.entity)
    type = type_fixture(scope.entity)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties/new")

    # The app shell binds a global Escape keydown; the form must not crash on it.
    assert view |> element("#tugas-shell") |> render_keydown() =~ "New duty"

    view
    |> form("#duty-create-form", %{
      "duty" => %{
        "title" => "EPF June",
        "duty_type_id" => type.id,
        "primary_assignee_id" => assignee.id,
        "due_by" => "2026-06-30",
        "open_note" => "Submit on time"
      }
    })
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    assert path =~ "/duties/"
  end

  test "manager creates duty with collaborators", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    assignee = member_fixture(manager.entity)
    collaborator = member_fixture(manager.entity)
    type = type_fixture(manager.entity)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duties/new")

    view
    |> form("#duty-create-form", %{
      "duty" => %{
        "title" => "EPF with helpers",
        "duty_type_id" => type.id,
        "primary_assignee_id" => assignee.id,
        "due_by" => "2026-06-30",
        "open_note" => "Opened with helpers",
        "collaborator_ids" => [collaborator.id]
      }
    })
    |> render_submit()

    assert_redirect(view)

    [created] = Duties.list_team_overview(manager)
    duty = Duties.get_duty!(manager, created.id)
    assert Enum.map(duty.collaborators, & &1.user_id) == [collaborator.id]
  end

  test "primary assignee becomes a dropdown listing other collaborators", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    assignee = member_fixture(manager.entity)
    collaborator = member_fixture(manager.entity)
    type = type_fixture(manager.entity)

    {:ok, with_collab} =
      Duties.create_duty(manager, %{
        title: "Shared work",
        duty_type_id: type.id,
        primary_assignee_id: assignee.id,
        collaborator_ids: [collaborator.id],
        due_by: ~D[2026-06-30],
        open_note: "open"
      })

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duties/#{with_collab.id}")

    assert has_element?(view, "#assignees-toggle", assignee.email)
    assert has_element?(view, "#assignees-dropdown", collaborator.email)

    # With no other collaborators, the primary stays a plain badge (no dropdown).
    {:ok, solo} =
      Duties.create_duty(manager, %{
        title: "Solo work",
        duty_type_id: type.id,
        primary_assignee_id: assignee.id,
        due_by: ~D[2026-06-30],
        open_note: "open"
      })

    {:ok, solo_view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duties/#{solo.id}")

    refute has_element?(solo_view, "#assignees-toggle")
    assert render(solo_view) =~ assignee.email
  end

  test "completion modal: clicking a required slot scopes the modal to that slot", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    member = member_fixture(manager.entity)

    type =
      type_fixture(manager.entity, complete_documents: "receipt,statutory_form")

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "EPF June",
        duty_type_id: type.id,
        primary_assignee_id: member.id,
        due_by: ~D[2026-06-30],
        open_note: "EPF opened"
      })

    seed_document(manager, duty, "receipt", "receipt.pdf")
    seed_document(manager, duty, "statutory_form", "form.pdf")

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duties/#{duty.id}")

    # Clicking the receipt slot scopes the modal to only that slot's row.
    view |> element("#open-completion-slot-receipt") |> render_click()
    assert has_element?(view, "#completion-slot-receipt", "receipt.pdf")
    refute has_element?(view, "#completion-slot-statutory_form")
    refute has_element?(view, "#select-slot-receipt")
    view |> element("#close-completion-modal") |> render_click()

    # Clicking the other slot scopes to it instead.
    view |> element("#open-completion-slot-statutory_form") |> render_click()
    assert has_element?(view, "#completion-slot-statutory_form", "form.pdf")
    refute has_element?(view, "#completion-slot-receipt")
  end

  test "completion slot offers a direct-upload Choose file button when unsatisfied", %{
    conn: conn
  } do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "EPF June",
        duty_type_id: type.id,
        due_by: ~D[2026-06-30],
        open_note: "EPF opened"
      })

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duties/#{duty.id}")

    view |> element("#open-completion-slot-receipt") |> render_click()

    # The button drives the UploadDirect hook (plain HTTP POST), not a socket
    # upload — it points at the controller endpoint for this duty.
    assert has_element?(
             view,
             "#select-slot-receipt[phx-hook='UploadDirect']" <>
               "[data-upload-url='/entities/#{manager.entity.slug}/duties/#{duty.id}/documents']"
           )
  end

  test "open_documents_from_done persists the completion modal for reconnect", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "EPF June",
        duty_type_id: type.id,
        due_by: ~D[2026-06-30],
        open_note: "EPF opened"
      })

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duties/#{duty.id}")

    view |> element("#duty-show") |> render_hook("open_documents_from_done", %{})

    assert_push_event(view, "persist_completion_modal", %{})
    assert has_element?(view, "#completion-modal")
  end

  test "reconnect: restore_completion_modal reopens the completion modal", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "EPF June",
        duty_type_id: type.id,
        due_by: ~D[2026-06-30],
        open_note: "EPF opened"
      })

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duties/#{duty.id}")

    refute has_element?(view, "#completion-modal")

    view
    |> element("#duty-show")
    |> render_hook("restore_completion_modal", %{"slot" => "receipt"})

    assert has_element?(view, "#completion-modal")
    assert has_element?(view, "#completion-slot-receipt")
  end

  test "reconnect: restore_step_files reopens the step files modal", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, complete_documents: "")

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "EPF June",
        duty_type_id: type.id,
        due_by: ~D[2026-06-30],
        open_note: "EPF opened"
      })

    duty = Duties.get_duty!(manager, duty.id)
    [open_event] = Enum.filter(duty.events, &(&1.status == "open"))

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duties/#{duty.id}")

    refute has_element?(view, "#step-files-modal-#{open_event.id}")

    view
    |> element("#duty-show")
    |> render_hook("restore_step_files", %{"event_id" => open_event.id})

    assert has_element?(view, "#step-files-modal-#{open_event.id}")
  end

  test "completion modal: deleting a required-slot file within 48h reopens the slot uploader", %{
    conn: conn
  } do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    member = member_fixture(manager.entity)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "EPF June",
        duty_type_id: type.id,
        primary_assignee_id: member.id,
        due_by: ~D[2026-06-30],
        open_note: "EPF opened"
      })

    seed_document(manager, duty, "receipt", "receipt.pdf")

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duties/#{duty.id}")

    view |> element("#open-completion-slot-receipt") |> render_click()

    # Slot is now satisfied: file shown, select button gone.
    duty = Duties.get_duty!(manager, duty.id)
    [open_event] = Enum.filter(duty.events, &(&1.status == "open"))
    document = hd(open_event.documents)

    assert has_element?(view, "#completion-slot-receipt", "receipt.pdf")
    assert has_element?(view, "#delete-doc-#{document.id}")
    refute has_element?(view, "#select-slot-receipt")

    # Deleting requires confirmation, then reopens the slot's uploader.
    view |> element("#delete-doc-#{document.id}") |> render_click()
    assert has_element?(view, "#confirm-delete-doc-#{document.id}")
    view |> element("#confirm-delete-doc-#{document.id}") |> render_click()
    assert has_element?(view, "#select-slot-receipt")
  end

  test "start_progress from show page requires progress note modal", %{conn: conn} do
    {scope, duty} = assigned_member_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties/#{duty.id}")

    view |> element("#start-progress-btn") |> render_click()
    assert has_element?(view, "#progress-modal")

    view
    |> form("#progress-form", %{"progress" => %{"note" => "Gathering receipts"}})
    |> render_submit()

    assert render(view) =~ "in_progress"
    assert render(view) =~ "Gathering receipts"
  end

  test "completed duty hides urgency and relative due label", %{conn: conn} do
    {scope, duty} = recurring_primary_scope_fixture(interval: "monthly")
    conn = log_in_user(conn, scope.user)

    {:ok, completed, _} =
      Duties.complete(scope, duty, %{
        note: "Done",
        next_due_by: ~D[2026-02-15]
      })

    {:ok, view, html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties/#{completed.id}")

    refute has_element?(view, "[data-urgency]")
    assert html =~ "Completed"
    refute html =~ "overdue"
    refute html =~ "Due soon"
    refute html =~ "due in"
    refute html =~ "days overdue"
  end

  test "skipped duty hides urgency and relative due label", %{conn: conn} do
    {scope, duty} = manager_duty_scope_fixture()
    conn = log_in_user(conn, scope.user)

    assert {:ok, _, nil} =
             Duties.skip(scope, duty, %{note: "No longer needed"})

    {:ok, view, html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties/#{duty.id}")

    refute has_element?(view, "[data-urgency]")
    assert html =~ "Skipped"
    refute html =~ "overdue"
    refute html =~ "Due soon"
  end

  test "skip button is shown for all live cycles (recurring and one-off)", %{conn: conn} do
    {scope, duty} = recurring_manager_scope_fixture(interval: "monthly")
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties/#{duty.id}")

    refute has_element?(view, "#cancel-btn")
    assert has_element?(view, "#skip-btn")

    {scope2, duty2} = manager_duty_scope_fixture()
    conn2 = log_in_user(build_conn(), scope2.user)

    {:ok, view2, _html} =
      live(conn2, ~p"/entities/#{scope2.entity.slug}/duties/#{duty2.id}")

    refute has_element?(view2, "#cancel-btn")
    assert has_element?(view2, "#skip-btn")
  end

  test "skip modal requires reason and next due", %{conn: conn} do
    {scope, duty} = recurring_manager_scope_fixture(interval: "monthly")
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties/#{duty.id}")

    view |> element("#skip-btn") |> render_click()
    assert has_element?(view, "#skip-modal")

    view
    |> form("#skip-form", %{"skip" => %{"note" => "", "next_due_by" => ""}})
    |> render_submit()

    assert render(view) =~ "A reason is required"

    view |> element("#skip-btn") |> render_click()

    view
    |> form("#skip-form", %{"skip" => %{"note" => "Deferred", "next_due_by" => ""}})
    |> render_submit()

    assert render(view) =~ "Next due date is required"
  end

  test "skip modal submits and spawns next cycle", %{conn: conn} do
    {scope, duty} = recurring_manager_scope_fixture(interval: "monthly")
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties/#{duty.id}")

    view |> element("#skip-btn") |> render_click()

    view
    |> form("#skip-form", %{
      "skip" => %{"note" => "Deferred", "next_due_by" => "2026-02-15"}
    })
    |> render_submit()

    assert_redirect(view, ~p"/entities/#{scope.entity.slug}/duties")
    assert Duties.get_duty!(scope, duty.id).closed_at

    live_cycles =
      scope
      |> Duties.list_duties(status: :live)
      |> Enum.filter(&(&1.series_id == duty.series_id))

    assert length(live_cycles) == 1
    assert hd(live_cycles).due_by == ~D[2026-02-15]
  end

  test "escape closes open modals", %{conn: conn} do
    {scope, duty} = manager_duty_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties/#{duty.id}")

    view |> element("#skip-btn") |> render_click()
    assert has_element?(view, "#skip-modal")

    view |> element("#tugas-shell") |> render_keydown()
    refute has_element?(view, "#skip-modal")

    view |> element("#done-btn") |> render_click()
    assert has_element?(view, "#done-modal")

    view |> element("#tugas-shell") |> render_keydown()
    refute has_element?(view, "#done-modal")
  end

  test "skip modal closes a one-off cycle", %{conn: conn} do
    {scope, duty} = manager_duty_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties/#{duty.id}")

    view |> element("#skip-btn") |> render_click()
    assert has_element?(view, "#skip-modal")

    view
    |> form("#skip-form", %{"skip" => %{"note" => "Not needed"}})
    |> render_submit()

    assert_redirect(view, ~p"/entities/#{scope.entity.slug}/duties")
    assert Duties.get_duty!(scope, duty.id).closed_at
  end

  test "skip modal requires a reason for one-off", %{conn: conn} do
    {scope, duty} = manager_duty_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties/#{duty.id}")

    view |> element("#skip-btn") |> render_click()
    assert has_element?(view, "#skip-modal")

    view |> form("#skip-form", %{"skip" => %{"note" => ""}}) |> render_submit()
    assert render(view) =~ "A reason is required"
  end

  test "end series modal requires a reason", %{conn: conn} do
    {scope, duty} = recurring_manager_scope_fixture(interval: "monthly")
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties/#{duty.id}")

    view |> element("#end-series-btn") |> render_click()
    assert has_element?(view, "#end-series-modal")

    view |> form("#end-series-form", %{"end_series" => %{"note" => ""}}) |> render_submit()
    assert render(view) =~ "A reason is required"
  end

  test "end series flow closes recurring series and redirects", %{conn: conn} do
    {scope, duty} = recurring_manager_scope_fixture(interval: "monthly")
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties/#{duty.id}")

    view |> element("#end-series-btn") |> render_click()
    assert has_element?(view, "#end-series-modal")

    view
    |> form("#end-series-form", %{"end_series" => %{"note" => "Client left"}})
    |> render_submit()

    assert_redirect(view, ~p"/entities/#{scope.entity.slug}/duties")

    ended = Duties.get_duty!(scope, duty.id)
    assert ended.series_ended_at
  end

  test "mark done is hidden while a required document is missing", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    member_scope = member_scope_on_entity(manager.entity)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "EPF Jan",
        duty_type_id: type.id,
        primary_assignee_id: member_scope.user.id,
        due_by: ~D[2026-06-15],
        open_note: "Open"
      })

    conn = log_in_user(conn, member_scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duties/#{duty.id}")

    # Required "receipt" is missing → no Mark done, but the completion path is offered.
    refute has_element?(view, "#done-btn")
    assert has_element?(view, "#open-completion-slot-receipt")
  end

  test "mark done appears once required documents are fulfilled", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "EPF Jan",
        duty_type_id: type.id,
        primary_assignee_id: manager.user.id,
        due_by: ~D[2026-06-15],
        open_note: "Open"
      })

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duties/#{duty.id}")

    refute has_element?(view, "#done-btn")

    # Attach the required receipt (as the UploadDirect/controller path would),
    # then the client signals the LiveView to refresh.
    seed_document(manager, duty, "receipt", "receipt.pdf")
    view |> element("#duty-show") |> render_hook("document_uploaded", %{})

    # Slot satisfied → Mark done becomes available.
    assert has_element?(view, "#done-btn")
  end

  test "completed slot shows satisfied in the summary, files not under timeline events", %{
    conn: conn
  } do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "EPF Jan",
        duty_type_id: type.id,
        primary_assignee_id: manager.user.id,
        due_by: ~D[2026-06-15],
        open_note: "Open"
      })

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duties/#{duty.id}")

    # Move to in_progress so the workable event is the in_progress one.
    view |> element("#start-progress-btn") |> render_click()
    view |> form("#progress-form", %{"progress" => %{"note" => "Working"}}) |> render_submit()

    # Attach the required receipt — it physically attaches to the in_progress event.
    seed_document(manager, duty, "receipt", "receipt.pdf")
    view |> element("#duty-show") |> render_hook("document_uploaded", %{})

    # The slot is surfaced as a thumbnail in the summary; required files stay off the timeline.
    assert has_element?(
             view,
             "#completion-summary #summary-slot-receipt a[data-doc-kind='pdf'][data-doc-name='receipt.pdf']"
           )

    refute has_element?(view, "#completion-summary #summary-slot-receipt .hero-plus-mini")

    duty = Duties.get_duty!(manager, duty.id)

    for event <- duty.events do
      refute has_element?(view, "#event-files-#{event.id}", "receipt.pdf")
    end
  end

  test "done modal requires next due for recurring duties", %{conn: conn} do
    {scope, duty} = recurring_primary_scope_fixture(interval: "monthly")
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties/#{duty.id}")

    view |> element("#done-btn") |> render_click()
    assert has_element?(view, "#done-modal")

    view
    |> form("#done-form", %{"done" => %{"next_due_by" => "", "note" => "Done"}})
    |> render_submit()

    assert render(view) =~ "Next due date is required"
  end

  test "manager corrects duty title from show page", %{conn: conn} do
    {scope, duty} = manager_duty_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties/#{duty.id}")

    duty = Duties.get_duty!(scope, duty.id)

    view |> element("#edit-duty-btn") |> render_click()
    assert has_element?(view, "#edit-duty-form")
    assert has_element?(view, "#edit-duty-type", duty.duty_type.name)

    view
    |> form("#edit-duty-form", %{
      "duty" => %{
        "title" => "EPF June (corrected)",
        "due_by" => Date.to_iso8601(duty.due_by),
        "primary_assignee_id" => duty.primary_assignee_id
      }
    })
    |> render_submit()

    assert render(view) =~ "EPF June (corrected)"
    refute has_element?(view, "#audit-log")

    view |> element("#show-corrections-btn") |> render_click()
    assert has_element?(view, "#audit-log", "title")
    assert has_element?(view, "#show-corrections-btn", "Hide corrections")

    # The same button toggles the corrections back closed.
    view |> element("#show-corrections-btn") |> render_click()
    refute has_element?(view, "#audit-log")
    assert has_element?(view, "#show-corrections-btn", "Show corrections")
  end

  test "manager updates collaborators from edit modal", %{conn: conn} do
    {scope, duty} = manager_duty_scope_fixture()
    conn = log_in_user(conn, scope.user)
    collab = member_fixture(scope.entity)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties/#{duty.id}")

    view |> element("#edit-duty-btn") |> render_click()

    view
    |> form("#edit-duty-form", %{
      "duty" => %{
        "title" => duty.title,
        "due_by" => Date.to_iso8601(duty.due_by),
        "primary_assignee_id" => duty.primary_assignee_id,
        "collaborator_ids" => [collab.id]
      }
    })
    |> render_submit()

    updated = Duties.get_duty!(scope, duty.id)
    assert Enum.map(updated.collaborators, & &1.user_id) == [collab.id]
    assert render(view) =~ collab.email
  end

  test "manager removes collaborators from edit modal", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    assignee = member_fixture(manager.entity)
    collaborator = member_fixture(manager.entity)
    type = type_fixture(manager.entity)

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "With collaborators",
        duty_type_id: type.id,
        primary_assignee_id: assignee.id,
        due_by: ~D[2026-06-30],
        open_note: "With collaborators",
        collaborator_ids: [collaborator.id]
      })

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duties/#{duty.id}")

    view |> element("#edit-duty-btn") |> render_click()

    view
    |> form("#edit-duty-form", %{
      "duty" => %{
        "title" => duty.title,
        "due_by" => Date.to_iso8601(duty.due_by),
        "primary_assignee_id" => duty.primary_assignee_id,
        "collaborator_ids" => []
      }
    })
    |> render_submit()

    updated = Duties.get_duty!(manager, duty.id)
    assert updated.collaborators == []
  end

  test "manager edits event note from show page", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    assignee = member_fixture(manager.entity)
    type = type_fixture(manager.entity)

    {:ok, created} =
      Duties.create_duty(manager, %{
        title: "SST Return",
        duty_type_id: type.id,
        primary_assignee_id: assignee.id,
        due_by: ~D[2026-06-30],
        open_note: "Orginal typo"
      })

    duty = Duties.get_duty!(manager, created.id)
    event = hd(duty.events)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duties/#{duty.id}")

    view |> element("#edit-note-#{event.id}") |> render_click()

    view
    |> form("#note-form-#{event.id}", %{"note" => %{"note" => "Original typo"}})
    |> render_submit()

    assert render(view) =~ "Original typo"

    view |> element("#show-corrections-btn") |> render_click()
    assert has_element?(view, "#audit-log", "note")
  end

  test "series sibling links on show page", %{conn: conn} do
    {scope, duty} = recurring_primary_scope_fixture(interval: "monthly")
    conn = log_in_user(conn, scope.user)

    assert {:ok, first, second} =
             Duties.complete(scope, duty, %{note: "Done", next_due_by: ~D[2026-02-15]})

    assert {:ok, middle, third} =
             Duties.complete(scope, second, %{note: "Done", next_due_by: ~D[2026-03-15]})

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties/#{middle.id}")

    assert has_element?(view, "#duty-series-nav-previous")
    assert has_element?(view, "#duty-series-nav-next")

    previous_href = ~p"/entities/#{scope.entity.slug}/duties/#{first.id}"
    next_href = ~p"/entities/#{scope.entity.slug}/duties/#{third.id}"

    assert render(view) =~ previous_href
    assert render(view) =~ next_href

    {:ok, first_view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties/#{first.id}")

    refute has_element?(first_view, "#duty-series-nav-previous")
    assert has_element?(first_view, "#duty-series-nav-next")

    {:ok, last_view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties/#{third.id}")

    assert has_element?(last_view, "#duty-series-nav-previous")
    refute has_element?(last_view, "#duty-series-nav-next")
  end

  test "complete recurring duty with next due spawns successor", %{conn: conn} do
    {scope, duty} = recurring_primary_scope_fixture(interval: "monthly")
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/duties/#{duty.id}")

    view |> element("#done-btn") |> render_click()

    view
    |> form("#done-form", %{"done" => %{"next_due_by" => "2026-07-15", "note" => "Done"}})
    |> render_submit()

    assert_redirect(view, ~p"/entities/#{scope.entity.slug}/duties")
  end

  test "completion modal: satisfied slot shows file, unsatisfied shows uploader", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    member = member_fixture(manager.entity)
    type = type_fixture(manager.entity, complete_documents: "receipt,form")

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "EPF June",
        duty_type_id: type.id,
        primary_assignee_id: member.id,
        due_by: ~D[2026-06-30],
        open_note: "EPF opened"
      })

    # Attach into the "receipt" slot (the cycle's workable open event).
    seed_document(manager, duty, "receipt", "receipt.pdf")

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duties/#{duty.id}")

    duty = Duties.get_duty!(manager, duty.id)
    [open_event] = Enum.filter(duty.events, &(&1.status == "open"))
    doc = hd(open_event.documents)

    # receipt slot, scoped on its own: satisfied (shows file + Delete, no uploader).
    view |> element("#open-completion-slot-receipt") |> render_click()
    assert has_element?(view, "#completion-slot-receipt", "receipt.pdf")
    assert has_element?(view, "#delete-doc-#{doc.id}")
    refute has_element?(view, "#completion-slot-form")
    refute has_element?(view, "#select-slot-receipt")
    # the file attached to the cycle's workable (open) event
    assert doc.document_slot == "receipt"
    view |> element("#close-completion-modal") |> render_click()

    # form slot, scoped on its own: unsatisfied (shows uploader).
    view |> element("#open-completion-slot-form") |> render_click()
    assert has_element?(view, "#select-slot-form")
    refute has_element?(view, "#completion-slot-receipt")
  end

  test "completion modal: voided required file shows in voided section, downloadable", %{
    conn: conn
  } do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "EPF",
        duty_type_id: type.id,
        due_by: ~D[2026-06-30],
        open_note: "open"
      })

    event = hd(Duties.list_events(duty))

    {:ok, doc} =
      Duties.add_document(manager, duty, event, upload_fixture("r.pdf"), "receipt")

    # Backdate inserted_at past the 48-hour edit window so the doc becomes voidable.
    old_doc =
      doc
      |> Ecto.Changeset.change(
        inserted_at: DateTime.add(DateTime.utc_now(:second), -49 * 3600, :second)
      )
      |> Tugas.Repo.update!()

    {:ok, _} = Duties.void_document(manager, duty, old_doc, %{reason: "wrong"})

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duties/#{duty.id}")

    view |> element("#open-completion-slot-receipt") |> render_click()

    assert has_element?(view, "#completion-voided", "r.pdf")
    assert has_element?(view, "#voided-doc-#{doc.id} a[href*='/documents/#{doc.id}']")
  end

  test "completion modal: void button hidden once the cycle is completed", %{conn: conn} do
    # Entity creator is admin — for whom voiding a locked-cycle file is otherwise allowed.
    admin = Tugas.EntitiesFixtures.entity_scope_fixture()
    conn = log_in_user(conn, admin.user)
    type = type_fixture(admin.entity, complete_documents: "receipt")

    {:ok, duty} =
      Duties.create_duty(admin, %{
        title: "EPF",
        duty_type_id: type.id,
        primary_assignee_id: admin.user.id,
        due_by: ~D[2026-06-30],
        open_note: "open"
      })

    event = hd(Duties.list_events(duty))

    {:ok, doc} =
      Duties.add_document(admin, duty, event, upload_fixture("r.pdf"), "receipt")

    duty = Duties.get_duty!(admin, duty.id)
    {:ok, completed, _} = Duties.complete(admin, duty, %{note: "Done"})

    # Admin could void this locked-cycle file at the context level...
    assert Duties.document_voidable?(admin, completed, doc)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{admin.entity.slug}/duties/#{completed.id}")

    view |> element("#open-completion-slot-receipt") |> render_click()

    # ...but the modal hides the Void button for a non-live cycle.
    assert has_element?(view, "#completion-slot-receipt", "r.pdf")
    refute has_element?(view, "#void-doc-#{doc.id}")
  end

  test "step files modal: additional (no-slot) file appears per step, not in completion view", %{
    conn: conn
  } do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "EPF",
        duty_type_id: type.id,
        due_by: ~D[2026-06-30],
        open_note: "open"
      })

    duty = Duties.get_duty!(manager, duty.id)
    [open_event] = Enum.filter(duty.events, &(&1.status == "open"))

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duties/#{duty.id}")

    # Attach an additional (no-slot) file to this step, then refresh the view.
    {:ok, _} =
      Duties.add_document(manager, duty, open_event, upload_fixture("notes.pdf"), nil)

    view |> element("#step-files-btn-#{open_event.id}") |> render_click()
    view |> element("#duty-show") |> render_hook("document_uploaded", %{})

    # A successful upload auto-closes the modal; reopen it to confirm the
    # additional file is filed under this step.
    refute has_element?(view, "#step-files-#{open_event.id}")
    view |> element("#step-files-btn-#{open_event.id}") |> render_click()
    assert has_element?(view, "#step-files-#{open_event.id}", "notes.pdf")

    duty = Duties.get_duty!(manager, duty.id)
    documents = Duties.list_cycle_documents(duty)

    assert Enum.any?(
             documents,
             &(is_nil(&1.document_slot) and &1.file["original"] == "notes.pdf")
           )
  end

  test "step files modal: voided other file shows in step voided area, downloadable", %{
    conn: conn
  } do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "EPF",
        duty_type_id: type.id,
        due_by: ~D[2026-06-30],
        open_note: "open"
      })

    event = hd(Duties.list_events(duty))

    {:ok, doc} =
      Duties.add_document(manager, duty, event, upload_fixture("n.pdf"), nil)

    # Backdate inserted_at past the 48-hour edit window so the doc becomes voidable.
    old_doc =
      doc
      |> Ecto.Changeset.change(
        inserted_at: DateTime.add(DateTime.utc_now(:second), -49 * 3600, :second)
      )
      |> Tugas.Repo.update!()

    {:ok, _} = Duties.void_document(manager, duty, old_doc, %{reason: "dup"})

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duties/#{duty.id}")

    view |> element("#step-files-btn-#{event.id}") |> render_click()

    assert has_element?(view, "#step-voided-#{event.id}", "n.pdf")
    assert has_element?(view, "#voided-doc-#{doc.id} a[href*='/documents/#{doc.id}']")
  end

  test "removing a required slot reclassifies a live duty's file as supporting", %{
    conn: conn
  } do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "EPF",
        duty_type_id: type.id,
        due_by: ~D[2026-06-30],
        open_note: "open"
      })

    event = hd(Duties.list_events(duty))

    {:ok, _doc} =
      Duties.add_document(manager, duty, event, upload_fixture("r.pdf"), "receipt")

    # Admin drops the "receipt" slot from the type.
    {:ok, _type} = Duties.update_type(manager, type, %{complete_documents: "form"})

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duties/#{duty.id}")

    duty = Duties.get_duty!(manager, duty.id)
    [open_event] = Enum.filter(duty.events, &(&1.status == "open"))

    # Completion view: receipt gone, "form" now required and unsatisfied; r.pdf not in slot rows.
    view |> element("#open-completion-slot-form") |> render_click()
    assert has_element?(view, "#completion-slot-form")
    refute has_element?(view, "#completion-slot-receipt")
    refute has_element?(view, "#completion-docs", "r.pdf")
    view |> element("#close-completion-modal") |> render_click()

    # Step files: r.pdf now a supporting file on its step.
    view |> element("#step-files-btn-#{open_event.id}") |> render_click()
    assert has_element?(view, "#step-files-#{open_event.id}", "r.pdf")
  end

  test "create form can make a Someday (no due date) duty", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}/duties/new")

    view
    |> form("#duty-create-form",
      duty: %{
        title: "Improve onboarding docs",
        duty_type_id: type.id,
        someday: "true",
        due_by: "",
        open_note: "idea"
      }
    )
    |> render_submit()

    ob =
      Tugas.Duties.list_duties_page(manager, status: :live, sort: :someday, limit: :all).rows
      |> List.first()

    assert ob.title == "Improve onboarding docs"
    assert ob.due_by == nil
  end

  test "manager marks a completed cycle in error and is taken to the replacement", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)

    {:ok, duty} =
      Duties.create_duty(manager, %{
        title: "EPF Jan",
        duty_type_id: type.id,
        primary_assignee_id: manager.user.id,
        due_by: ~D[2026-06-15],
        open_note: "open"
      })

    {:ok, done, _} = Duties.complete(manager, duty, %{note: "Done"})

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duties/#{done.id}")

    assert has_element?(view, "#mark-error-btn")

    view |> element("#mark-error-btn") |> render_click()
    assert has_element?(view, "#correct-modal")

    view
    |> form("#correct-form", %{"correct" => %{"reason" => "Wrong figures"}})
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    replacement_id = path |> String.split("/") |> List.last()
    refute replacement_id == done.id

    # Original now shows the completed-in-error banner; replacement shows the replaces banner.
    {:ok, original_view, _} =
      live(conn, ~p"/entities/#{manager.entity.slug}/duties/#{done.id}")

    assert has_element?(original_view, "#completed-in-error-banner")
    refute has_element?(original_view, "#mark-error-btn")

    {:ok, replacement_view, _} = live(conn, path)
    assert has_element?(replacement_view, "#replaces-banner")
  end

  test "show page does not crash for a Someday duty of a recurring type", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, recurring_interval: "monthly")

    {:ok, ob} =
      Duties.create_duty(manager, %{
        title: "Monthly someday",
        duty_type_id: type.id,
        someday: true,
        open_note: "n"
      })

    {:ok, _view, html} = live(conn, ~p"/entities/#{manager.entity.slug}/duties/#{ob.id}")
    assert html =~ "Monthly someday"
  end

  test "show page renders a Someday duty and can promote it to a due date", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)

    {:ok, ob} =
      Duties.create_duty(manager, %{
        title: "Refresh brand assets",
        duty_type_id: type.id,
        someday: true,
        open_note: "n"
      })

    {:ok, view, html} = live(conn, ~p"/entities/#{manager.entity.slug}/duties/#{ob.id}")
    assert html =~ "Refresh brand assets"

    # promote: open edit modal, uncheck someday, set a due date, submit
    view |> element("#edit-duty-btn") |> render_click()
    assert has_element?(view, "#edit-duty-form")

    # toggle someday off so the due_by field appears
    view
    |> form("#edit-duty-form", duty: %{someday: "false"})
    |> render_change()

    view
    |> form("#edit-duty-form",
      duty: %{
        title: ob.title,
        due_by: "2026-09-01",
        someday: "false"
      }
    )
    |> render_submit()

    assert Tugas.Repo.reload(ob).due_by == ~D[2026-09-01]
  end
end
