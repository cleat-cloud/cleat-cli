defmodule Cleat.PackTest do
  use ExUnit.Case, async: true

  alias Cleat.Pack

  test "packs a directory, excluding node_modules and .git" do
    dir = Path.join(System.tmp_dir!(), "cleat-pack-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "node_modules"))
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    File.write!(Path.join(dir, "node_modules/x.js"), "x")
    on_exit(fn -> File.rm_rf(dir) end)

    assert {:ok, tarball} = Pack.pack(dir)
    on_exit(fn -> File.rm(tarball) end)

    assert File.exists?(tarball)
    {listing, 0} = System.cmd("tar", ["-tzf", tarball])
    refute listing =~ "node_modules"
    assert listing =~ "index.html"
  end

  test "packs a single file" do
    file = Path.join(System.tmp_dir!(), "cleat-pack-#{System.unique_integer([:positive])}.html")
    File.write!(file, "<html></html>")
    on_exit(fn -> File.rm(file) end)

    assert {:ok, tarball} = Pack.pack(file)
    on_exit(fn -> File.rm(tarball) end)

    {listing, 0} = System.cmd("tar", ["-tzf", tarball])
    assert listing =~ "index.html"
  end

  test "rejects a missing path" do
    assert {:error, message} = Pack.pack("/nope/does-not-exist")
    assert message =~ "not a file or directory"
  end

  test "removes the partial tarball when tar fails" do
    dir =
      Path.join(System.tmp_dir!(), "cleat-pack-fail-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    secret = Path.join(dir, "secret.txt")
    File.write!(secret, "x")
    File.chmod!(secret, 0o000)

    on_exit(fn ->
      File.chmod(secret, 0o600)
      File.rm_rf(dir)
    end)

    before = Path.wildcard(Path.join(System.tmp_dir!(), "cleat_pack_*.tar.gz"))

    case Pack.pack(dir) do
      {:error, _} ->
        after_paths = Path.wildcard(Path.join(System.tmp_dir!(), "cleat_pack_*.tar.gz"))
        assert after_paths == before

      {:ok, _} ->
        # running as root (e.g. some CI) — tar can read the file; skip the assertion
        :ok
    end
  end
end
