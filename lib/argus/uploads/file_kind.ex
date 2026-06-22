defmodule Argus.Uploads.FileKind do
  @moduledoc false

  @image_exts ~w(jpg jpeg png gif webp svg avif bmp)
  @video_exts ~w(mp4 webm mov ogg ogv m4v)

  @doc """
  Classifies a filename by extension into `:image`, `:video`, `:pdf`, or `:other`.
  """
  def classify(name) when is_binary(name) do
    ext = name |> Path.extname() |> String.trim_leading(".") |> String.downcase()

    cond do
      ext in @image_exts -> :image
      ext in @video_exts -> :video
      ext == "pdf" -> :pdf
      true -> :other
    end
  end

  def classify(_), do: :other
end
