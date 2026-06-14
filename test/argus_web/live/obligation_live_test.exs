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
        due_by: ~D[2026-06-30]
      })

    {:ok, to_complete} =
      Obligations.create_obligation(manager, %{
        title: "Beta Done",
        obligation_type_id: type.id,
        primary_assignee_id: member_scope.user.id,
        due_by: ~D[2026-05-30]
      })

    assert {:ok, completed, _} = Obligations.complete(member_scope, to_complete, %{})

    {:ok, to_cancel} =
      Obligations.create_obligation(manager, %{
        title: "Gamma Cancelled",
        obligation_type_id: type.id,
        primary_assignee_id: member_scope.user.id,
        due_by: ~D[2026-04-30]
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
        "collaborator_ids" => [collaborator.id]
      }
    })
    |> render_submit()

    assert_redirect(view)

    [created] = Obligations.list_team_overview(manager)
    obligation = Obligations.get_obligation!(manager, created.id)
    assert Enum.map(obligation.collaborators, & &1.user_id) == [collaborator.id]
  end

  test "manager uploads a document on the show page", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    member = member_fixture(manager.entity)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "EPF June",
        obligation_type_id: type.id,
        primary_assignee_id: member.id,
        due_by: ~D[2026-06-30]
      })

    obligation = Obligations.get_obligation!(manager, obligation.id)
    [open_event] = Enum.filter(obligation.events, &(&1.status == "open"))

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}")

    view |> element("#documents-btn-#{open_event.id}") |> render_click()
    assert has_element?(view, "#document-modal-#{open_event.id}")

    assert has_element?(view, "#slot-upload-#{open_event.id}-receipt")

    view
    |> element("#select-slot-#{open_event.id}-receipt")
    |> render_click()

    file =
      file_input(view, "#document-form-#{open_event.id}-active", :document, [
        %{name: "receipt.pdf", content: "scan", type: "application/pdf"}
      ])

    render_upload(file, "receipt.pdf")

    view
    |> form("#document-form-#{open_event.id}-active", %{
      "document_slot" => "receipt",
      "event_id" => open_event.id
    })
    |> render_submit()

    assert render(view) =~ "receipt.pdf"
    assert has_element?(view, "[data-status] .badge", "receipt")
  end

  test "manager uploads additional file without required slot", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    member = member_fixture(manager.entity)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "EPF June",
        obligation_type_id: type.id,
        primary_assignee_id: member.id,
        due_by: ~D[2026-06-30]
      })

    obligation = Obligations.get_obligation!(manager, obligation.id)
    [open_event] = Enum.filter(obligation.events, &(&1.status == "open"))

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}")

    view |> element("#documents-btn-#{open_event.id}") |> render_click()

    view
    |> element("#select-additional-#{open_event.id}")
    |> render_click()

    file =
      file_input(view, "#document-form-#{open_event.id}-active", :document, [
        %{name: "notes.pdf", content: "extra", type: "application/pdf"}
      ])

    render_upload(file, "notes.pdf")

    view
    |> form("#document-form-#{open_event.id}-active", %{
      "event_id" => open_event.id
    })
    |> render_submit()

    assert render(view) =~ "notes.pdf"
    refute has_element?(view, "#event-#{open_event.id} .badge", "receipt")
  end

  test "start_progress from show page", %{conn: conn} do
    {scope, obligation} = assigned_member_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#start-progress-btn") |> render_click()
    assert render(view) =~ "in_progress"
  end

  test "series history lists prior cycles after a recurring completion", %{conn: conn} do
    {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")
    conn = log_in_user(conn, scope.user)

    {:ok, _done, successor} =
      Obligations.complete(scope, obligation, %{next_due_by: ~D[2026-02-15]})

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/#{successor.id}")

    assert has_element?(view, "#series-history")
    assert has_element?(view, "#series-cycle-#{obligation.id}", "Completed")
    assert has_element?(view, "#series-cycle-#{successor.id}", "Current")
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

  test "done modal requires next due for recurring obligations", %{conn: conn} do
    {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#done-btn") |> render_click()
    assert has_element?(view, "#done-modal")

    view |> form("#done-form", %{"done" => %{"next_due_by" => ""}}) |> render_submit()

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

    view |> form("#done-form", %{"done" => %{"next_due_by" => "2026-07-15"}}) |> render_submit()

    assert_redirect(view, ~p"/entities/#{scope.entity.slug}/obligations")
  end
end
