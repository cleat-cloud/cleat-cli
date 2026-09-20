defmodule Cleat.RuntimeTest do
  use ExUnit.Case, async: false

  alias Cleat.Runtime

  setup do
    dir = Path.join(System.tmp_dir!(), "cleat-runtime-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    original = File.cwd!()
    File.cd!(dir)

    on_exit(fn ->
      File.cd!(original)
      File.rm_rf(dir)
    end)

    {:ok, dir: dir}
  end

  test "detects phoenix from mix.exs" do
    File.write!("mix.exs", "defmodule X do\n  def project, do: [app: :my_app]\nend\n")

    assert Runtime.detect() == "phoenix"
  end

  test "detects golang from go.mod" do
    File.write!("go.mod", "module example.com/x\n")

    assert Runtime.detect() == "golang"
  end

  test "prefers phoenix over golang when both go.mod and mix.exs exist" do
    File.write!("go.mod", "module example.com/x\n")
    File.write!("mix.exs", "defmodule X do\nend\n")

    assert Runtime.detect() == "phoenix"
  end

  test "detects a Next.js project as node" do
    File.write!(
      "package.json",
      ~s({"dependencies":{"next":"15.0.0"},"scripts":{"build":"next build"}})
    )

    assert Runtime.detect() == "node"
  end

  test "detects a TanStack Start project as node" do
    File.write!("package.json", ~s({"dependencies":{"@tanstack/react-start":"^1.0.0"}}))

    assert Runtime.detect() == "node"
  end

  test "detects a Rails project as rails" do
    File.write!("Gemfile", ~s(gem "rails", "~> 7.1"\n))
    File.mkdir_p!("config")
    File.write!("config/application.rb", "module App\nend\n")

    assert Runtime.detect() == "rails"
  end

  test "detects a bare package.json as static" do
    File.write!("package.json", ~s({"name":"site"}))

    assert Runtime.detect() == "static"
  end

  test "detects a plain html site as static" do
    File.write!("index.html", "<html></html>")

    assert Runtime.detect() == "static"
  end

  test "falls back to phoenix when nothing matches" do
    assert Runtime.detect() == "phoenix"
  end
end
