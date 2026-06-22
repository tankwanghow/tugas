defmodule ArgusWeb.LiveUpload do
  @moduledoc """
  Client-side upload configuration for the `UploadDirect` hook. Documents are
  uploaded over a plain HTTP request (see `ArgusWeb.DocumentController.create/2`),
  not LiveView's socket upload, so this module only exposes the data attributes
  the hook needs: image-resize config and the per-kind size limits.
  """

  alias Argus.Uploads.Limits

  @doc """
  Data attributes for the `UploadDirect` client hook: image-resize config plus
  the per-kind size limits (so it can reject oversized files before uploading
  and resize large images client-side).
  """
  def client_size_attrs do
    config = client_resize_config()

    %{
      "data-max-edge" => Integer.to_string(Map.get(config, :max_edge, 1920)),
      "data-quality" => Integer.to_string(Map.get(config, :quality, 85)),
      "data-min-bytes" => Integer.to_string(Map.get(config, :min_bytes, 50_000)),
      "data-limit-image" => Integer.to_string(Limits.limit_bytes("photo.jpg")),
      "data-limit-video" => Integer.to_string(Limits.limit_bytes("clip.mp4")),
      "data-limit-pdf" => Integer.to_string(Limits.limit_bytes("doc.pdf")),
      "data-limit-other" => Integer.to_string(Limits.limit_bytes("file.bin"))
    }
  end

  defp client_resize_config do
    case Application.get_env(:argus, :upload_client_image_resize, %{}) do
      config when is_map(config) -> config
      config when is_list(config) -> Map.new(config)
      _ -> %{}
    end
  end
end
