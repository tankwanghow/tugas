defmodule Argus.Obligations.TypeTest do
  use Argus.DataCase, async: true

  alias Argus.Obligations.Type

  describe "changeset/2" do
    test "rejects invalid reminder_offsets" do
      changeset =
        Type.changeset(%Type{}, %{
          name: "EPF",
          recurring_interval: "none",
          reminder_offsets: "7, ,abc"
        })

      refute changeset.valid?
      assert "must be comma-separated non-negative integers" in errors_on(changeset).reminder_offsets
    end

    test "normalizes reminder_offsets" do
      changeset =
        Type.changeset(%Type{}, %{
          name: "EPF",
          recurring_interval: "none",
          reminder_offsets: " 7,30,7 ,1 "
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :reminder_offsets) == "1,7,30"
    end

    test "rejects duplicate complete_documents slots" do
      changeset =
        Type.changeset(%Type{}, %{
          name: "EPF",
          recurring_interval: "none",
          complete_documents: "receipt,receipt"
        })

      refute changeset.valid?
      assert "has duplicate slot names" in errors_on(changeset).complete_documents
    end

    test "normalizes complete_documents" do
      changeset =
        Type.changeset(%Type{}, %{
          name: "EPF",
          recurring_interval: "none",
          complete_documents: " receipt , form , payment "
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :complete_documents) == "form,payment,receipt"
    end
  end
end