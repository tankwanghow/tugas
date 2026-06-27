defmodule ArgusWeb.DocumentControllerTest do
  use ArgusWeb.ConnCase, async: true

  alias Argus.Entities
  alias Argus.Obligations

  import Argus.EntitiesFixtures
  import Argus.ObligationsFixtures

  setup :register_and_log_in_user

  test "serves document when user is a member of the entity", %{conn: conn, user: user} do
    manager = manager_scope_fixture()

    %Entities.Membership{
      user_id: user.id,
      entity_id: manager.entity.id,
      role: "member",
      accepted_at: DateTime.utc_now(:second)
    }
    |> Entities.Membership.changeset(%{})
    |> Argus.Repo.insert!()

    {_, obligation} = obligation_fixture(manager)
    event = hd(Obligations.list_events(obligation))

    path = Path.join(System.tmp_dir!(), "serve_test_#{System.unique_integer()}.txt")
    File.write!(path, "file contents")

    upload = %Plug.Upload{
      path: path,
      filename: "serve_test.txt",
      content_type: "text/plain"
    }

    {:ok, document} =
      Obligations.add_document(manager, obligation, event, upload, nil)

    conn =
      get(
        conn,
        ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}/documents/#{document.id}"
      )

    assert response(conn, 200)
  end

  test "serves inline by default and as attachment with ?download=1", %{conn: conn, user: user} do
    manager = manager_scope_fixture()

    %Entities.Membership{
      user_id: user.id,
      entity_id: manager.entity.id,
      role: "member",
      accepted_at: DateTime.utc_now(:second)
    }
    |> Entities.Membership.changeset(%{})
    |> Argus.Repo.insert!()

    {_, obligation} = obligation_fixture(manager)
    event = hd(Obligations.list_events(obligation))

    path = Path.join(System.tmp_dir!(), "disp_test_#{System.unique_integer()}.txt")
    File.write!(path, "file contents")

    upload = %Plug.Upload{path: path, filename: "disp_test.txt", content_type: "text/plain"}
    {:ok, document} = Obligations.add_document(manager, obligation, event, upload, nil)

    base =
      ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}/documents/#{document.id}"

    inline_conn = get(conn, base)
    assert [disp] = get_resp_header(inline_conn, "content-disposition")
    assert disp =~ "inline"

    download_conn = get(conn, base <> "?download=1")
    assert [disp] = get_resp_header(download_conn, "content-disposition")
    assert disp =~ "attachment"
  end

  describe "create (multipart upload)" do
    test "uploads a document to the current workable event", %{conn: conn} do
      manager = manager_scope_fixture()
      conn = log_in_user(conn, manager.user)
      type = type_fixture(manager.entity, complete_documents: "receipt")

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-30],
          open_note: "open"
        })

      path = Path.join(System.tmp_dir!(), "create_#{System.unique_integer()}.pdf")
      File.write!(path, "receipt contents")

      conn =
        post(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}/documents", %{
          "file" => %Plug.Upload{
            path: path,
            filename: "receipt.pdf",
            content_type: "application/pdf"
          },
          "document_slot" => "receipt"
        })

      assert json_response(conn, 200)["ok"] == true

      obligation = Obligations.get_obligation!(manager, obligation.id)
      docs = Obligations.list_cycle_documents(obligation)

      assert Enum.any?(
               docs,
               &(&1.document_slot == "receipt" and &1.file["original"] == "receipt.pdf")
             )
    end

    test "rejects a video over the per-kind size limit with 413", %{conn: conn} do
      manager = manager_scope_fixture()
      conn = log_in_user(conn, manager.user)
      type = type_fixture(manager.entity, complete_documents: "receipt")

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-30],
          open_note: "open"
        })

      path = Path.join(System.tmp_dir!(), "big_#{System.unique_integer()}.mp4")
      File.write!(path, String.duplicate("x", 11_000_000))

      conn =
        post(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}/documents", %{
          "file" => %Plug.Upload{path: path, filename: "clip.mp4", content_type: "video/mp4"}
        })

      body = json_response(conn, 413)
      assert body["ok"] == false
      assert body["error"] =~ "max 10 MB for videos"
    end

    test "rejects an unknown completion slot with 422", %{conn: conn} do
      manager = manager_scope_fixture()
      conn = log_in_user(conn, manager.user)
      type = type_fixture(manager.entity, complete_documents: "receipt")

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-30],
          open_note: "open"
        })

      path = Path.join(System.tmp_dir!(), "bad_slot_#{System.unique_integer()}.pdf")
      File.write!(path, "x")

      conn =
        post(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}/documents", %{
          "file" => %Plug.Upload{
            path: path,
            filename: "extra.pdf",
            content_type: "application/pdf"
          },
          "document_slot" => "not_a_slot"
        })

      body = json_response(conn, 422)
      assert body["error"] =~ "not required"
    end

    test "rejects a duplicate completion slot upload with 409", %{conn: conn} do
      manager = manager_scope_fixture()
      conn = log_in_user(conn, manager.user)
      type = type_fixture(manager.entity, complete_documents: "receipt")

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-30],
          open_note: "open"
        })

      path1 = Path.join(System.tmp_dir!(), "slot1_#{System.unique_integer()}.pdf")
      path2 = Path.join(System.tmp_dir!(), "slot2_#{System.unique_integer()}.pdf")
      File.write!(path1, "first")
      File.write!(path2, "second")

      base = ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}/documents"

      post(conn, base, %{
        "file" => %Plug.Upload{
          path: path1,
          filename: "receipt.pdf",
          content_type: "application/pdf"
        },
        "document_slot" => "receipt"
      })

      conn =
        post(conn, base, %{
          "file" => %Plug.Upload{
            path: path2,
            filename: "receipt2.pdf",
            content_type: "application/pdf"
          },
          "document_slot" => "receipt"
        })

      body = json_response(conn, 409)
      assert body["error"] =~ "already has a file"
    end

    test "returns 403 when the member is not allowed to add documents", %{conn: conn} do
      manager = manager_scope_fixture()
      member = member_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type_fixture(manager.entity).id,
          due_by: ~D[2026-06-30],
          open_note: "open"
        })

      conn = log_in_user(conn, member)

      path = Path.join(System.tmp_dir!(), "denied_#{System.unique_integer()}.pdf")
      File.write!(path, "x")

      conn =
        post(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}/documents", %{
          "file" => %Plug.Upload{
            path: path,
            filename: "denied.pdf",
            content_type: "application/pdf"
          }
        })

      assert json_response(conn, 403)["ok"] == false
    end

    test "uploads a step file to a specific event_id", %{conn: conn} do
      manager = manager_scope_fixture()
      conn = log_in_user(conn, manager.user)
      type = type_fixture(manager.entity, complete_documents: "")

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-30],
          open_note: "open"
        })

      [open_event] = Enum.filter(Obligations.list_events(obligation), &(&1.status == "open"))

      path = Path.join(System.tmp_dir!(), "step_#{System.unique_integer()}.pdf")
      File.write!(path, "step file contents")

      conn =
        post(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}/documents", %{
          "file" => %Plug.Upload{
            path: path,
            filename: "notes.pdf",
            content_type: "application/pdf"
          },
          "event_id" => open_event.id
        })

      assert json_response(conn, 200)["ok"] == true

      obligation = Obligations.get_obligation!(manager, obligation.id)
      event = Enum.find(obligation.events, &(&1.id == open_event.id))

      assert Enum.any?(event.documents, &(&1.file["original"] == "notes.pdf"))
    end

    test "rejects an oversized image with 413", %{conn: conn} do
      manager = manager_scope_fixture()
      conn = log_in_user(conn, manager.user)
      type = type_fixture(manager.entity, complete_documents: "")

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-30],
          open_note: "open"
        })

      path = Path.join(System.tmp_dir!(), "big_img_#{System.unique_integer()}.jpg")
      File.write!(path, String.duplicate("x", 6_000_000))

      conn =
        post(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}/documents", %{
          "file" => %Plug.Upload{
            path: path,
            filename: "photo.jpg",
            content_type: "image/jpeg"
          }
        })

      body = json_response(conn, 413)
      assert body["ok"] == false
      assert body["error"] =~ "max"
    end
  end

  test "serves a voided document so it can still be downloaded", %{conn: conn} do
    manager = manager_scope_fixture()
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

    path = Path.join(System.tmp_dir!(), "receipt_#{System.unique_integer()}.pdf")
    File.write!(path, "receipt contents")

    upload = %Plug.Upload{
      path: path,
      filename: "receipt.pdf",
      content_type: "application/pdf"
    }

    {:ok, document} =
      Obligations.add_document(manager, obligation, event, upload, "receipt")

    # Make it old enough to be voidable (past 48 hour window)
    old_document =
      document
      |> Ecto.Changeset.change(
        inserted_at: DateTime.add(DateTime.utc_now(:second), -49 * 3600, :second)
      )
      |> Argus.Repo.update!()

    # Void it (admin, with reason).
    {:ok, _} =
      Obligations.void_document(manager, obligation, old_document, %{reason: "wrong file"})

    conn =
      get(
        conn,
        ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}/documents/#{old_document.id}"
      )

    assert response(conn, 200)
  end
end
