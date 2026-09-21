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

  test "detects an uppercase-extension html file", %{dir: dir} do
    file = Path.join(dir, "UPPER.HTML")
    File.write!(file, "<html></html>")

    assert Static.detect?(file)
  end

  test "detects an .htm file", %{dir: dir} do
    file = Path.join(dir, "page.htm")
    File.write!(file, "<html></html>")

    assert Static.detect?(file)
  end

  test "rejects a non-html file", %{dir: dir} do
    file = Path.join(dir, "notes.txt")
    File.write!(file, "not html")

    refute Static.detect?(file)
  end

  test "site_slug uses the folder name" do
    assert Static.site_slug(Path.join(System.tmp_dir!(), "Minha Loja/")) == "minha-loja"
  end

  test "site_slug uses the file rootname for a single html file" do
    assert Static.site_slug(Path.join(System.tmp_dir!(), "almanaque.html")) == "almanaque"
  end

  test "site_slug trims to a safe label" do
    assert Static.site_slug(Path.join(System.tmp_dir!(), "__weird--name__/")) == "weird-name"
  end

  test "site_slug returns nil for a symbol-only folder name" do
    assert Static.site_slug(Path.join(System.tmp_dir!(), "---")) == nil
  end
end
