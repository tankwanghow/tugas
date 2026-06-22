defmodule Argus.Uploads.Limits do
  @moduledoc false

  alias Argus.Uploads.FileKind

  @default_limits %{
    image: 5_000_000,
    video: 10_000_000,
    pdf: 20_000_000,
    other: 20_000_000
  }

  def max_upload_bytes do
    limits()
    |> Map.values()
    |> Enum.max()
  end

  def limit_bytes(filename) when is_binary(filename) do
    Map.fetch!(limits(), FileKind.classify(filename))
  end

  def validate_size(filename, size) when is_integer(size) and size >= 0 do
    limit = limit_bytes(filename)

    if size <= limit do
      :ok
    else
      {:error, too_large_message(FileKind.classify(filename), limit)}
    end
  end

  def validate_size(_filename, _size), do: :ok

  def too_large_message(kind, limit_bytes) do
    "File is too large (max #{human_mb(limit_bytes)} for #{kind_label(kind)})."
  end

  @doc """
  Short human summary of the per-kind size limits, e.g.
  `"Images ≤5 MB · videos ≤10 MB · PDFs ≤20 MB"`. Shown beside uploaders so
  users know the cap before picking a (potentially huge) camera video.
  """
  def summary do
    l = limits()

    "Images ≤#{human_mb(l[:image])} · videos ≤#{human_mb(l[:video])} · PDFs ≤#{human_mb(l[:pdf])}"
  end

  defp limits do
    Application.get_env(:argus, :upload_limits, @default_limits)
    |> normalize_config(@default_limits)
  end

  defp normalize_config(config, _default) when is_map(config), do: config
  defp normalize_config(config, _default) when is_list(config), do: Map.new(config)
  defp normalize_config(_config, default), do: default

  defp kind_label(:image), do: "images"
  defp kind_label(:video), do: "videos"
  defp kind_label(:pdf), do: "PDFs"
  defp kind_label(_), do: "this file type"

  defp human_mb(bytes), do: "#{div(bytes, 1_000_000)} MB"
end
