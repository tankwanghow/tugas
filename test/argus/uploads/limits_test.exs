defmodule Argus.Uploads.LimitsTest do
  use ExUnit.Case, async: true

  alias Argus.Uploads.Limits

  test "max_upload_bytes is the largest configured limit" do
    assert Limits.max_upload_bytes() == 20_000_000
  end

  test "validate_size accepts files within per-type limits" do
    assert :ok = Limits.validate_size("photo.jpg", 4_000_000)
    assert :ok = Limits.validate_size("clip.mp4", 9_000_000)
    assert :ok = Limits.validate_size("report.pdf", 19_000_000)
  end

  test "validate_size rejects files over per-type limits" do
    assert {:error, message} = Limits.validate_size("photo.jpg", 6_000_000)
    assert message =~ "5 MB"
    assert message =~ "images"

    assert {:error, message} = Limits.validate_size("clip.mp4", 11_000_000)
    assert message =~ "10 MB"
    assert message =~ "videos"
  end
end
