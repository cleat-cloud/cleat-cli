defmodule Cleat.Commands.InitTest do
  use ExUnit.Case, async: false

  alias Cleat.Commands.Init

  setup do
    dir =
      Path.join(System.tmp_dir!(), "cleat-init-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    original = File.cwd!()
    File.cd!(dir)

    on_exit(fn ->
      File.cd!(original)
      File.rm_rf(dir)
    end)

    {:ok, dir: dir}
  end

  test "writes a phoenix manifest using the mix app name" do
    File.write!("mix.exs", "defmodule X do\n  def project, do: [app: :my_app]\nend\n")

    assert :ok = Init.run(%{})

    manifest = read_manifest()
    assert manifest["runtime"] == "phoenix"
    assert manifest["release_name"] == "my_app"
    assert manifest["memory_max_mb"] == 400
  end

  test "detects a golang project and its command binaries" do
    File.write!("go.mod", "module example.com/x\n")
    File.mkdir_p!("cmd/server")
    File.write!("cmd/server/main.go", "package main\n")
    File.mkdir_p!("cmd/worker")
    File.write!("cmd/worker/main.go", "package main\n")

    assert :ok = Init.run(%{})

    manifest = read_manifest()
    assert manifest["runtime"] == "golang"
    assert manifest["binaries"] == ["server", "worker"]
  end

  test "honours explicit options" do
    assert :ok =
             Init.run(%{
               runtime: "phoenix",
               release_name: "custom",
               memory_max_mb: 800,
               solo_server: true,
               caddy_mode: "replace"
             })

    manifest = read_manifest()
    assert manifest["release_name"] == "custom"
    assert manifest["memory_max_mb"] == 800
    assert manifest["solo_server"] == true
    assert manifest["caddy_mode"] == "replace"
  end

  test "refuses to overwrite without --yes" do
    File.mkdir_p!(".cleat_deploy")
    File.write!(".cleat_deploy/deploy.json", "{}")

    assert {:error, message} = Init.run(%{})
    assert message =~ "--yes"

    assert :ok = Init.run(%{yes: true})
    assert read_manifest()["runtime"] == "phoenix"
  end

  test "detects a static site without mix.exs or go.mod" do
    File.write!("index.html", "<html></html>")

    assert :ok = Init.run(%{})

    manifest = read_manifest()
    assert manifest["runtime"] == "static"
    refute Map.has_key?(manifest, "release_name")
  end

  test "detects a JS project with package.json as static" do
    File.write!("package.json", ~s({"name":"site"}))

    assert :ok = Init.run(%{})

    assert read_manifest()["runtime"] == "static"
  end

  test "detects a Next.js project as node" do
    File.write!(
      "package.json",
      ~s({"name":"app","dependencies":{"next":"15.0.0"},"scripts":{"build":"next build","start":"next start"}})
    )

    assert :ok = Init.run(%{})

    manifest = read_manifest()
    assert manifest["runtime"] == "node"
    refute Map.has_key?(manifest, "release_name")
  end

  test "detects a TanStack Start project as node" do
    File.write!(
      "package.json",
      ~s({"name":"app","dependencies":{"@tanstack/react-start":"^1.0.0"}})
    )

    assert :ok = Init.run(%{})

    assert read_manifest()["runtime"] == "node"
  end

  test "detects a Rails project as rails" do
    File.write!("Gemfile", ~s(source "https://rubygems.org"\ngem "rails", "~> 7.1"\n))
    File.mkdir_p!("config")
    File.write!("config/application.rb", "module App\nend\n")

    assert :ok = Init.run(%{})

    manifest = read_manifest()
    assert manifest["runtime"] == "rails"
    refute Map.has_key?(manifest, "release_name")
  end

  test "writes a rails ruby_version option" do
    assert :ok = Init.run(%{runtime: "rails", ruby_version: "3.2.2"})

    manifest = read_manifest()
    assert manifest["runtime"] == "rails"
    assert manifest["ruby_version"] == "3.2.2"
  end

  test "writes node build/start/node_version options" do
    assert :ok =
             Init.run(%{
               runtime: "node",
               build_command: "npm run build:prod",
               start_command: "npm start",
               node_version: "20"
             })

    manifest = read_manifest()
    assert manifest["runtime"] == "node"
    assert manifest["build_command"] == "npm run build:prod"
    assert manifest["start_command"] == "npm start"
    assert manifest["node_version"] == "20"
  end

  defp read_manifest do
    ".cleat_deploy/deploy.json"
    |> File.read!()
    |> Jason.decode!()
  end
end
