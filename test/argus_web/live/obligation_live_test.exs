defmodule ArgusWeb.ObligationLiveTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Argus.ObligationsFixtures

  alias Argus.Obligations

  setup :register_and_log_in_user

  test "obligation index filters completed and cancelled cycles", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    member_scope = member_scope_on_entity(manager.entity)
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity)

    {:ok, live_obligation} =
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

    {:ok, to_cancel} =
      Obligations.create_obligation(manager, %{
        title: "Gamma Cancelled",
        obligation_type_id: type.id,
        primary_assignee_id: member_scope.user.id,
        due_by: ~D[2026-04-30],
        open_note: "Gamma"
      })

    assert {:ok, _} =
             Obligations.cancel_obligation(manager, to_cancel, %{note: "No longer needed"})

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}/obligations")

    assert has_element?(view, "#obligation-#{live_obligation.id}")
    refute has_element?(view, "#obligation-#{completed.id}")

    view |> element("#filter-completed") |> render_click()
    assert has_element?(view, "#obligation-#{completed.id}")
    refute has_element?(view, "#obligation-#{live_obligation.id}")

    view |> element("#filter-cancelled") |> render_click()
    assert has_element?(view, "#obligation-#{to_cancel.id}")

    member_conn = log_in_user(conn, member_scope.user)

    {:ok, member_view, _html} =
      live(member_conn, ~p"/entities/#{manager.entity.slug}/obligations")

    member_view |> element("#filter-my_live") |> render_click()
    assert has_element?(member_view, "#obligation-#{live_obligation.id}")

    member_view |> element("#filter-my_completed") |> render_click()
    assert has_element?(member_view, "#obligation-#{completed.id}")

    view |> element("#filter-live") |> render_click()
    view |> element("#obligation-search") |> render_keyup(%{"value" => "Alpha"})
    assert has_element?(view, "#obligation-#{live_obligation.id}")
    refute has_element?(view, "#obligation-#{to_cancel.id}")
  end

  test "manager creates obligation via form", %{conn: conn} do
    {scope, _} = manager_obligation_scope_fixture()
    conn = log_in_user(conn, scope.user)
    assignee = member_fixture(scope.entity)
    type = type_fixture(scope.entity)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/new")

    view
    |> form("#obligation-create-form", %{
      "obligation" => %{
        "title" => "EPF June",
        "obligation_type_id" => type.id,
        "primary_assignee_id" => assignee.id,
        "due_by" => "2026-06-30",
        "open_note" => "Submit on time"
      }
    })
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    assert path =~ "/obligations/"
  end

  test "manager creates obligation with general file attachment", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    assignee = member_fixture(manager.entity)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/new")

    file =
      file_input(view, "#create-document-form", :document, [
        %{name: "notes.pdf", content: "extra", type: "application/pdf"}
      ])

    render_upload(file, "notes.pdf")

    assert has_element?(view, "#staged-documents", "notes.pdf")

    view
    |> form("#obligation-create-form", %{
      "obligation" => %{
        "title" => "EPF with notes",
        "obligation_type_id" => type.id,
        "primary_assignee_id" => assignee.id,
        "due_by" => "2026-06-30",
        "open_note" => "Opened with notes"
      }
    })
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    obligation_id = path |> String.split("/") |> List.last()

    obligation = Obligations.get_obligation!(manager, obligation_id)
    documents = Obligations.list_cycle_documents(obligation)

    assert Enum.any?(
             documents,
             &(is_nil(&1.document_slot) and &1.file["original"] == "notes.pdf")
           )

    refute Enum.any?(documents, &(&1.document_slot == "receipt"))
  end

  test "manager can remove a chosen attachment before creating", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    assignee = member_fixture(manager.entity)
    type = type_fixture(manager.entity)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/new")

    file =
      file_input(view, "#create-document-form", :document, [
        %{name: "notes.pdf", content: "extra", type: "application/pdf"}
      ])

    render_upload(file, "notes.pdf")
    assert has_element?(view, "#staged-documents", "notes.pdf")

    view |> element("#staged-documents button", "Remove") |> render_click()
    refute has_element?(view, "#staged-documents", "notes.pdf")

    view
    |> form("#obligation-create-form", %{
      "obligation" => %{
        "title" => "EPF no attachment",
        "obligation_type_id" => type.id,
        "primary_assignee_id" => assignee.id,
        "due_by" => "2026-06-30",
        "open_note" => "Opened without notes"
      }
    })
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    obligation_id = path |> String.split("/") |> List.last()
    obligation = Obligations.get_obligation!(manager, obligation_id)
    assert Obligations.list_cycle_documents(obligation) == []
  end

  test "manager creates obligation with collaborators", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    assignee = member_fixture(manager.entity)
    collaborator = member_fixture(manager.entity)
    type = type_fixture(manager.entity)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/new")

    view
    |> form("#obligation-create-form", %{
      "obligation" => %{
        "title" => "EPF with helpers",
        "obligation_type_id" => type.id,
        "primary_assignee_id" => assignee.id,
        "due_by" => "2026-06-30",
        "open_note" => "Opened with helpers",
        "collaborator_ids" => [collaborator.id]
      }
    })
    |> render_submit()

    assert_redirect(view)

    [created] = Obligations.list_team_overview(manager)
    obligation = Obligations.get_obligation!(manager, created.id)
    assert Enum.map(obligation.collaborators, & &1.user_id) == [collaborator.id]
  end

  test "completion modal: manager stages files for two slots and uploads individually", %{
    conn: conn
  } do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    member = member_fixture(manager.entity)

    type =
      type_fixture(manager.entity, complete_documents: "receipt,statutory_form")

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "EPF June",
        obligation_type_id: type.id,
        primary_assignee_id: member.id,
        due_by: ~D[2026-06-30],
        open_note: "EPF opened"
      })

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}")

    view |> element("#open-completion-modal") |> render_click()

    # Stage receipt slot.
    view |> element("#select-slot-receipt") |> render_click()

    file =
      file_input(view, "#completion-upload-form", :document, [
        %{name: "receipt.pdf", content: "scan", type: "application/pdf"}
      ])

    render_upload(file, "receipt.pdf")
    view |> form("#completion-upload-form", %{"picker_slot" => "receipt"}) |> render_change()
    assert has_element?(view, "#upload-slot-receipt")

    # Upload receipt slot; statutory_form should still have its uploader.
    view |> element("#upload-slot-receipt") |> render_click()
    assert render(view) =~ "Document added"
    assert has_element?(view, "#select-slot-statutory_form")
    refute has_element?(view, "#upload-slot-receipt")

    # Stage and upload statutory_form slot.
    view |> element("#select-slot-statutory_form") |> render_click()

    file2 =
      file_input(view, "#completion-upload-form", :document, [
        %{name: "form.pdf", content: "scan", type: "application/pdf"}
      ])

    render_upload(file2, "form.pdf")

    view
    |> form("#completion-upload-form", %{"picker_slot" => "statutory_form"})
    |> render_change()

    view |> element("#upload-slot-statutory_form") |> render_click()
    assert render(view) =~ "Document added"
    assert render(view) =~ "receipt.pdf"
    assert render(view) =~ "form.pdf"
  end

  test "completion modal: deleting a required-slot file within 48h reopens the slot uploader", %{
    conn: conn
  } do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    member = member_fixture(manager.entity)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "EPF June",
        obligation_type_id: type.id,
        primary_assignee_id: member.id,
        due_by: ~D[2026-06-30],
        open_note: "EPF opened"
      })

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}")

    view |> element("#open-completion-modal") |> render_click()

    # Upload a file into the "receipt" slot.
    view |> element("#select-slot-receipt") |> render_click()

    file =
      file_input(view, "#completion-upload-form", :document, [
        %{name: "receipt.pdf", content: "scan", type: "application/pdf"}
      ])

    render_upload(file, "receipt.pdf")
    view |> form("#completion-upload-form", %{"picker_slot" => "receipt"}) |> render_change()
    view |> element("#upload-slot-receipt") |> render_click()

    # Slot is now satisfied: file shown, select button gone.
    obligation = Obligations.get_obligation!(manager, obligation.id)
    [open_event] = Enum.filter(obligation.events, &(&1.status == "open"))
    document = hd(open_event.documents)

    assert has_element?(view, "#completion-slot-receipt", "receipt.pdf")
    assert has_element?(view, "#delete-doc-#{document.id}")
    refute has_element?(view, "#select-slot-receipt")

    # Deleting requires confirmation, then reopens the slot's uploader.
    view |> element("#delete-doc-#{document.id}") |> render_click()
    assert has_element?(view, "#confirm-delete-doc-#{document.id}")
    view |> element("#confirm-delete-doc-#{document.id}") |> render_click()
    assert render(view) =~ "Document deleted"
    assert has_element?(view, "#select-slot-receipt")
  end

  test "start_progress from show page requires progress note modal", %{conn: conn} do
    {scope, obligation} = assigned_member_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#start-progress-btn") |> render_click()
    assert has_element?(view, "#progress-modal")

    view
    |> form("#progress-form", %{"progress" => %{"note" => "Gathering receipts"}})
    |> render_submit()

    assert render(view) =~ "in_progress"
    assert render(view) =~ "Gathering receipts"
  end

  test "completed obligation hides urgency and relative due label", %{conn: conn} do
    {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")
    conn = log_in_user(conn, scope.user)

    {:ok, completed, _} =
      Obligations.complete(scope, obligation, %{
        note: "Done",
        next_due_by: ~D[2026-02-15]
      })

    {:ok, view, html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/#{completed.id}")

    refute has_element?(view, "[data-urgency]")
    assert html =~ "Completed"
    refute html =~ "overdue"
    refute html =~ "Due soon"
    refute html =~ "due in"
    refute html =~ "days overdue"
  end

  test "cancelled obligation hides urgency and relative due label", %{conn: conn} do
    {scope, obligation} = manager_obligation_scope_fixture()
    conn = log_in_user(conn, scope.user)

    assert {:ok, _} =
             Obligations.cancel_obligation(scope, obligation, %{note: "No longer needed"})

    {:ok, view, html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}")

    refute has_element?(view, "[data-urgency]")
    assert html =~ "Cancelled"
    refute html =~ "overdue"
    refute html =~ "Due soon"
  end

  test "recurring obligation shows skip instead of cancel", %{conn: conn} do
    {scope, obligation} = recurring_manager_scope_fixture(interval: "monthly")
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}")

    refute has_element?(view, "#cancel-btn")
    assert has_element?(view, "#skip-btn")
  end

  test "skip modal requires reason and next due", %{conn: conn} do
    {scope, obligation} = recurring_manager_scope_fixture(interval: "monthly")
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}")

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
    {scope, obligation} = recurring_manager_scope_fixture(interval: "monthly")
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#skip-btn") |> render_click()

    view
    |> form("#skip-form", %{
      "skip" => %{"note" => "Deferred", "next_due_by" => "2026-02-15"}
    })
    |> render_submit()

    assert_redirect(view, ~p"/entities/#{scope.entity.slug}/obligations")
    assert Obligations.get_obligation!(scope, obligation.id).status == "cancelled"

    live_cycles =
      scope
      |> Obligations.list_obligations(status: :live)
      |> Enum.filter(&(&1.series_id == obligation.series_id))

    assert length(live_cycles) == 1
    assert hd(live_cycles).due_by == ~D[2026-02-15]
  end

  test "escape closes open modals", %{conn: conn} do
    {scope, obligation} = manager_obligation_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#cancel-btn") |> render_click()
    assert has_element?(view, "#cancel-modal")

    view |> element("#argus-shell") |> render_keydown()
    refute has_element?(view, "#cancel-modal")

    view |> element("#done-btn") |> render_click()
    assert has_element?(view, "#done-modal")

    view |> element("#argus-shell") |> render_keydown()
    refute has_element?(view, "#done-modal")
  end

  test "cancel modal requires a reason", %{conn: conn} do
    {scope, obligation} = manager_obligation_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#cancel-btn") |> render_click()
    assert has_element?(view, "#cancel-modal")

    view |> form("#cancel-form", %{"cancel" => %{"note" => ""}}) |> render_submit()
    assert render(view) =~ "A reason is required"
  end

  test "cancel modal submits reason and redirects", %{conn: conn} do
    {scope, obligation} = manager_obligation_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#cancel-btn") |> render_click()

    view
    |> form("#cancel-form", %{"cancel" => %{"note" => "Duplicate entry"}})
    |> render_submit()

    assert_redirect(view, ~p"/entities/#{scope.entity.slug}/obligations")
    assert Obligations.get_obligation!(scope, obligation.id).status == "cancelled"
  end

  test "end series modal requires a reason", %{conn: conn} do
    {scope, obligation} = recurring_manager_scope_fixture(interval: "monthly")
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#end-series-btn") |> render_click()
    assert has_element?(view, "#end-series-modal")

    view |> form("#end-series-form", %{"end_series" => %{"note" => ""}}) |> render_submit()
    assert render(view) =~ "A reason is required"
  end

  test "mark done is hidden while a required document is missing", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    member_scope = member_scope_on_entity(manager.entity)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "EPF Jan",
        obligation_type_id: type.id,
        primary_assignee_id: member_scope.user.id,
        due_by: ~D[2026-06-15],
        open_note: "Open"
      })

    conn = log_in_user(conn, member_scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}")

    # Required "receipt" is missing → no Mark done, but the completion path is offered.
    refute has_element?(view, "#done-btn")
    assert has_element?(view, "#open-completion-modal")
  end

  test "mark done appears once required documents are fulfilled", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "EPF Jan",
        obligation_type_id: type.id,
        primary_assignee_id: manager.user.id,
        due_by: ~D[2026-06-15],
        open_note: "Open"
      })

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}")

    refute has_element?(view, "#done-btn")

    # Upload the required receipt via the completion modal.
    view |> element("#open-completion-modal") |> render_click()
    view |> element("#select-slot-receipt") |> render_click()

    file =
      file_input(view, "#completion-upload-form", :document, [
        %{name: "receipt.pdf", content: "scan", type: "application/pdf"}
      ])

    render_upload(file, "receipt.pdf")
    view |> form("#completion-upload-form", %{"picker_slot" => "receipt"}) |> render_change()
    view |> element("#upload-slot-receipt") |> render_click()

    # Slot satisfied → Mark done becomes available.
    assert has_element?(view, "#done-btn")
  end

  test "completion files show in the summary, not under timeline events", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "EPF Jan",
        obligation_type_id: type.id,
        primary_assignee_id: manager.user.id,
        due_by: ~D[2026-06-15],
        open_note: "Open"
      })

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}")

    # Move to in_progress so the workable event is the in_progress one.
    view |> element("#start-progress-btn") |> render_click()
    view |> form("#progress-form", %{"progress" => %{"note" => "Working"}}) |> render_submit()

    # Upload the required receipt — it physically attaches to the in_progress event.
    view |> element("#open-completion-modal") |> render_click()
    view |> element("#select-slot-receipt") |> render_click()

    file =
      file_input(view, "#completion-upload-form", :document, [
        %{name: "receipt.pdf", content: "scan", type: "application/pdf"}
      ])

    render_upload(file, "receipt.pdf")
    view |> form("#completion-upload-form", %{"picker_slot" => "receipt"}) |> render_change()
    view |> element("#upload-slot-receipt") |> render_click()

    # The completion file shows beside the slot in the summary, not in the timeline.
    assert has_element?(view, "#completion-summary", "receipt.pdf")

    obligation = Obligations.get_obligation!(manager, obligation.id)

    for event <- obligation.events do
      refute has_element?(view, "#event-files-#{event.id}", "receipt.pdf")
    end
  end

  test "done modal requires next due for recurring obligations", %{conn: conn} do
    {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#done-btn") |> render_click()
    assert has_element?(view, "#done-modal")

    view
    |> form("#done-form", %{"done" => %{"next_due_by" => "", "note" => "Done"}})
    |> render_submit()

    assert render(view) =~ "Next due date is required"
  end

  test "manager corrects obligation title from show page", %{conn: conn} do
    {scope, obligation} = manager_obligation_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#edit-obligation-btn") |> render_click()
    assert has_element?(view, "#edit-obligation-form")

    view
    |> form("#edit-obligation-form", %{
      "obligation" => %{
        "title" => "EPF June (corrected)",
        "due_by" => Date.to_iso8601(obligation.due_by),
        "primary_assignee_id" => obligation.primary_assignee_id
      }
    })
    |> render_submit()

    assert render(view) =~ "EPF June (corrected)"
    refute has_element?(view, "#audit-log")

    view |> element("#show-corrections-btn") |> render_click()
    assert has_element?(view, "#audit-log", "title")
  end

  test "manager updates collaborators from edit modal", %{conn: conn} do
    {scope, obligation} = manager_obligation_scope_fixture()
    conn = log_in_user(conn, scope.user)
    collab = member_fixture(scope.entity)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#edit-obligation-btn") |> render_click()

    view
    |> form("#edit-obligation-form", %{
      "obligation" => %{
        "title" => obligation.title,
        "due_by" => Date.to_iso8601(obligation.due_by),
        "primary_assignee_id" => obligation.primary_assignee_id,
        "collaborator_ids" => [collab.id]
      }
    })
    |> render_submit()

    updated = Obligations.get_obligation!(scope, obligation.id)
    assert Enum.map(updated.collaborators, & &1.user_id) == [collab.id]
    assert render(view) =~ collab.email
  end

  test "manager removes collaborators from edit modal", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    assignee = member_fixture(manager.entity)
    collaborator = member_fixture(manager.entity)
    type = type_fixture(manager.entity)

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "With collaborators",
        obligation_type_id: type.id,
        primary_assignee_id: assignee.id,
        due_by: ~D[2026-06-30],
        open_note: "With collaborators",
        collaborator_ids: [collaborator.id]
      })

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}")

    view |> element("#edit-obligation-btn") |> render_click()

    view
    |> form("#edit-obligation-form", %{
      "obligation" => %{
        "title" => obligation.title,
        "due_by" => Date.to_iso8601(obligation.due_by),
        "primary_assignee_id" => obligation.primary_assignee_id,
        "collaborator_ids" => []
      }
    })
    |> render_submit()

    updated = Obligations.get_obligation!(manager, obligation.id)
    assert updated.collaborators == []
  end

  test "manager edits event note from show page", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    assignee = member_fixture(manager.entity)
    type = type_fixture(manager.entity)

    {:ok, created} =
      Obligations.create_obligation(manager, %{
        title: "SST Return",
        obligation_type_id: type.id,
        primary_assignee_id: assignee.id,
        due_by: ~D[2026-06-30],
        open_note: "Orginal typo"
      })

    obligation = Obligations.get_obligation!(manager, created.id)
    event = hd(obligation.events)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}")

    view |> element("#edit-note-#{event.id}") |> render_click()

    view
    |> form("#note-form-#{event.id}", %{"note" => %{"note" => "Original typo"}})
    |> render_submit()

    assert render(view) =~ "Original typo"

    view |> element("#show-corrections-btn") |> render_click()
    assert has_element?(view, "#audit-log", "note")
  end

  test "complete recurring obligation with next due spawns successor", %{conn: conn} do
    {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#done-btn") |> render_click()

    view
    |> form("#done-form", %{"done" => %{"next_due_by" => "2026-07-15", "note" => "Done"}})
    |> render_submit()

    assert_redirect(view, ~p"/entities/#{scope.entity.slug}/obligations")
  end

  test "completion modal: satisfied slot shows file, unsatisfied shows uploader", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    member = member_fixture(manager.entity)
    type = type_fixture(manager.entity, complete_documents: "receipt,form")

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "EPF June",
        obligation_type_id: type.id,
        primary_assignee_id: member.id,
        due_by: ~D[2026-06-30],
        open_note: "EPF opened"
      })

    obligation = Obligations.get_obligation!(manager, obligation.id)
    [_open_event] = Enum.filter(obligation.events, &(&1.status == "open"))

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}")

    view |> element("#open-completion-modal") |> render_click()

    # Upload into the "receipt" slot from the cycle modal (no event id in the form).
    view |> element("#select-slot-receipt") |> render_click()

    file =
      file_input(view, "#completion-upload-form", :document, [
        %{name: "receipt.pdf", content: "scan", type: "application/pdf"}
      ])

    render_upload(file, "receipt.pdf")
    view |> form("#completion-upload-form", %{"picker_slot" => "receipt"}) |> render_change()
    view |> element("#upload-slot-receipt") |> render_click()

    # receipt satisfied (shows file + Delete), form still unsatisfied (shows uploader).
    obligation = Obligations.get_obligation!(manager, obligation.id)
    [open_event] = Enum.filter(obligation.events, &(&1.status == "open"))
    doc = hd(open_event.documents)

    assert has_element?(view, "#completion-slot-receipt", "receipt.pdf")
    assert has_element?(view, "#delete-doc-#{doc.id}")
    assert has_element?(view, "#select-slot-form")
    # the file attached to the cycle's workable (open) event
    assert doc.document_slot == "receipt"
  end

  test "completion modal: voided required file shows in voided section, downloadable", %{
    conn: conn
  } do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "EPF",
        obligation_type_id: type.id,
        due_by: ~D[2026-06-30],
        open_note: "open"
      })

    event = hd(Obligations.list_events(obligation))

    {:ok, doc} =
      Obligations.add_document(manager, obligation, event, upload_fixture("r.pdf"), "receipt")

    # Backdate inserted_at past the 48-hour edit window so the doc becomes voidable.
    old_doc =
      doc
      |> Ecto.Changeset.change(
        inserted_at: DateTime.add(DateTime.utc_now(:second), -49 * 3600, :second)
      )
      |> Argus.Repo.update!()

    {:ok, _} = Obligations.void_document(manager, obligation, old_doc, %{reason: "wrong"})

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}")

    view |> element("#open-completion-modal") |> render_click()

    assert has_element?(view, "#completion-voided", "r.pdf")
    assert has_element?(view, "#voided-doc-#{doc.id} a[href*='/documents/#{doc.id}']")
  end

  test "completion modal: void button hidden once the cycle is completed", %{conn: conn} do
    # Entity creator is admin — for whom voiding a locked-cycle file is otherwise allowed.
    admin = Argus.EntitiesFixtures.entity_scope_fixture()
    conn = log_in_user(conn, admin.user)
    type = type_fixture(admin.entity, complete_documents: "receipt")

    {:ok, obligation} =
      Obligations.create_obligation(admin, %{
        title: "EPF",
        obligation_type_id: type.id,
        primary_assignee_id: admin.user.id,
        due_by: ~D[2026-06-30],
        open_note: "open"
      })

    event = hd(Obligations.list_events(obligation))

    {:ok, doc} =
      Obligations.add_document(admin, obligation, event, upload_fixture("r.pdf"), "receipt")

    obligation = Obligations.get_obligation!(admin, obligation.id)
    {:ok, completed, _} = Obligations.complete(admin, obligation, %{note: "Done"})

    # Admin could void this locked-cycle file at the context level...
    assert Obligations.document_voidable?(admin, completed, doc)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{admin.entity.slug}/obligations/#{completed.id}")

    view |> element("#open-completion-modal") |> render_click()

    # ...but the modal hides the Void button for a non-live cycle.
    assert has_element?(view, "#completion-slot-receipt", "r.pdf")
    refute has_element?(view, "#void-doc-#{doc.id}")
  end

  test "step files modal: additional (no-slot) file appears per step, not in completion view", %{
    conn: conn
  } do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "EPF",
        obligation_type_id: type.id,
        due_by: ~D[2026-06-30],
        open_note: "open"
      })

    obligation = Obligations.get_obligation!(manager, obligation.id)
    [open_event] = Enum.filter(obligation.events, &(&1.status == "open"))

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}")

    view |> element("#step-files-btn-#{open_event.id}") |> render_click()
    view |> element("#select-additional-#{open_event.id}") |> render_click()

    file =
      file_input(view, "#step-upload-form-#{open_event.id}", :document, [
        %{name: "notes.pdf", content: "x", type: "application/pdf"}
      ])

    render_upload(file, "notes.pdf")

    view
    |> form("#step-upload-form-#{open_event.id}", %{"picker_slot" => "additional"})
    |> render_change()

    view |> element("#upload-additional-#{open_event.id}") |> render_click()

    assert has_element?(view, "#step-files-#{open_event.id}", "notes.pdf")

    obligation = Obligations.get_obligation!(manager, obligation.id)
    documents = Obligations.list_cycle_documents(obligation)

    assert Enum.any?(
             documents,
             &(is_nil(&1.document_slot) and &1.file["original"] == "notes.pdf")
           )
  end

  test "step files modal: voided other file shows in step voided area, downloadable", %{
    conn: conn
  } do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "EPF",
        obligation_type_id: type.id,
        due_by: ~D[2026-06-30],
        open_note: "open"
      })

    event = hd(Obligations.list_events(obligation))

    {:ok, doc} =
      Obligations.add_document(manager, obligation, event, upload_fixture("n.pdf"), nil)

    # Backdate inserted_at past the 48-hour edit window so the doc becomes voidable.
    old_doc =
      doc
      |> Ecto.Changeset.change(
        inserted_at: DateTime.add(DateTime.utc_now(:second), -49 * 3600, :second)
      )
      |> Argus.Repo.update!()

    {:ok, _} = Obligations.void_document(manager, obligation, old_doc, %{reason: "dup"})

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}")

    view |> element("#step-files-btn-#{event.id}") |> render_click()

    assert has_element?(view, "#step-voided-#{event.id}", "n.pdf")
    assert has_element?(view, "#voided-doc-#{doc.id} a[href*='/documents/#{doc.id}']")
  end

  test "removing a required slot reclassifies a live obligation's file as supporting", %{
    conn: conn
  } do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "EPF",
        obligation_type_id: type.id,
        due_by: ~D[2026-06-30],
        open_note: "open"
      })

    event = hd(Obligations.list_events(obligation))

    {:ok, _doc} =
      Obligations.add_document(manager, obligation, event, upload_fixture("r.pdf"), "receipt")

    # Admin drops the "receipt" slot from the type.
    {:ok, _type} = Obligations.update_type(manager, type, %{complete_documents: "form"})

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}")

    obligation = Obligations.get_obligation!(manager, obligation.id)
    [open_event] = Enum.filter(obligation.events, &(&1.status == "open"))

    # Completion view: receipt gone, "form" now required and unsatisfied; r.pdf not in slot rows.
    view |> element("#open-completion-modal") |> render_click()
    assert has_element?(view, "#completion-slot-form")
    refute has_element?(view, "#completion-slot-receipt")
    refute has_element?(view, "#completion-docs", "r.pdf")
    view |> element("#close-completion-modal") |> render_click()

    # Step files: r.pdf now a supporting file on its step.
    view |> element("#step-files-btn-#{open_event.id}") |> render_click()
    assert has_element?(view, "#step-files-#{open_event.id}", "r.pdf")
  end

  test "manager marks a completed cycle in error and is taken to the replacement", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
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
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{done.id}")

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
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{done.id}")

    assert has_element?(original_view, "#completed-in-error-banner")
    refute has_element?(original_view, "#mark-error-btn")

    {:ok, replacement_view, _} = live(conn, path)
    assert has_element?(replacement_view, "#replaces-banner")
  end

  defp upload_fixture(filename, content \\ "hello") do
    path = Path.join(System.tmp_dir!(), "#{System.unique_integer()}_#{filename}")
    File.write!(path, content)

    %Plug.Upload{
      path: path,
      filename: filename,
      content_type: "application/pdf"
    }
  end
end
