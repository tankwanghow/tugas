defmodule Argus.Todos.PaginationTest do
  use ExUnit.Case, async: true

  alias Argus.Todos.Pagination

  test "encode/decode round-trip" do
    cursor = %{key: "2026-06-25T12:00:00Z", id: Ecto.UUID.generate()}
    assert cursor |> Pagination.encode() |> Pagination.decode() == cursor
  end

  test "nil and invalid cursors decode to nil" do
    assert Pagination.encode(nil) == nil
    assert Pagination.decode(nil) == nil
    assert Pagination.decode("") == nil
    assert Pagination.decode("not-base64-$$$") == nil
    assert Pagination.decode(Base.url_encode64("not json", padding: false)) == nil
  end
end
