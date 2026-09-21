defmodule Cleat.StaticTest do
  use ExUnit.Case, async: true

  alias Cleat.Static

  setup do
    dir = Path.join(System.tmp_dir!(), "cleat-static-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, dir: dir}
  end

  test "detects a single html file" do
    file = Path.join(System.tmp_dir!(), "cleat-static-#{System.unique_integer([:positive])}.html")
    File.write!(file, "<html></html>")
    on_exit(fn -> File.rm(file) end)

    assert Static.detect?(file)
  end

  test "detects a directory with index.html and no build file", %{dir: dir} do
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    File.write!(Path.join(dir, "app.css"), "body{}")

    assert Static.detect?(dir)
  end

  test "rejects a node project with index.html", %{dir: dir} do
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    File.write!(Path.join(dir, "package.json"), ~s({"name":"x"}))

    refute Static.detect?(dir)
  end

  test "rejects a mix project", %{dir: dir} do
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    File.write!(Path.join(dir, "mix.exs"), "defmodule X do\nend\n")

    refute Static.detect?(dir)
  end

  test "rejects a go project", %{dir: dir} do
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    File.write!(Path.join(dir, "go.mod"), "module x\n")

    refute Static.detect?(dir)
  end

  test "rejects a directory without an index.html", %{dir: dir} do
    File.write!(Path.join(dir, "about.html"), "<html></html>")

    refute Static.detect?(dir)
  end

  test "site_slug uses the folder name" do
    assert Static.site_slug("/tmp/Minha Loja/") == "minha-loja"
  end

  test "site_slug uses the file rootname for a single html file" do
    assert Static.site_slug("/tmp/almanaque.html") == "almanaque"
  end

  test "site_slug trims to a safe label" do
    assert Static.site_slug("/tmp/__weird--name__/") == "weird-name"
  end
end
