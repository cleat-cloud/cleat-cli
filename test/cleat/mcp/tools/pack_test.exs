defmodule Cleat.MCP.Tools.PackTest do
  use ExUnit.Case, async: true

  alias Cleat.MCP.Tools.Pack

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
end
