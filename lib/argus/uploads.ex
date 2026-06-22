defmodule Argus.Uploads do
  @moduledoc """
  Local filesystem storage for obligation event documents.
  """

  alias Argus.Uploads.Limits

  def store(%Plug.Upload{} = upload, entity_id, obligation_id) do
    with :ok <- validate_upload_size(upload) do
      dest_dir = Path.join([base_dir(), to_string(entity_id), to_string(obligation_id)])
      File.mkdir_p!(dest_dir)
      filename = "#{Ecto.UUID.generate()}_#{upload.filename}"
      dest = Path.join(dest_dir, filename)
      File.cp!(upload.path, dest)
      %{filename: filename, original: upload.filename, path: dest}
    end
  end

  defp validate_upload_size(%Plug.Upload{path: path, filename: filename}) do
    size =
      case File.stat(path) do
        {:ok, %{size: size}} -> size
        _ -> 0
      end

    case Limits.validate_size(filename, size) do
      :ok -> :ok
      {:error, _message} -> {:error, :file_too_large}
    end
  end

  def delete(%{file: file}) when is_map(file) do
    case file_path(file) do
      path when is_binary(path) -> File.rm(path)
      _ -> :ok
    end
  end

  def delete(_), do: :ok

  def path(%{file: file}) when is_map(file), do: file_path(file)

  defp base_dir do
    Application.get_env(:argus, :uploads_dir, Path.join(:code.priv_dir(:argus), "uploads"))
  end

  defp file_path(file) do
    Map.get(file, "path") || Map.get(file, :path)
  end
end
