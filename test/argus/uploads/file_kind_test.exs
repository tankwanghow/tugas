defmodule Argus.Uploads.FileKindTest do
  use ExUnit.Case, async: true

  alias Argus.Uploads.FileKind

  test "classify/1 groups common extensions" do
    assert FileKind.classify("photo.JPG") == :image
    assert FileKind.classify("clip.mp4") == :video
    assert FileKind.classify("report.pdf") == :pdf
    assert FileKind.classify("notes.txt") == :other
  end
end
