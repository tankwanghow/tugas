defmodule Argus.Todos.Pagination do
  @moduledoc false

  def encode(nil), do: nil

  def encode(%{key: key, id: id}) do
    %{"k" => key, "id" => id}
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  def decode(nil), do: nil
  def decode(""), do: nil
  def decode(%{key: _, id: _} = cursor), do: cursor

  def decode(cursor) when is_binary(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, %{"k" => key, "id" => id}} <- Jason.decode(json) do
      %{key: key, id: id}
    else
      _ -> nil
    end
  end

  def decode(_), do: nil
end
