defmodule Cleat.Commands.DeployTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Cleat.Commands.Deploy

  @isolated_env ~w(CLEAT_CONFIG CLEAT_BASE_DOMAIN CLEAT_SITES_BASE_DOMAIN)

  # Isolate from the developer's real config file and domain env vars so a
  # static host fallback cannot pick up unrelated values.
  setup do
    Application.put_env(:cleat_cli, :req_plug, {Req.Test, __MODULE__})

    path = Path.join(System.tmp_dir!(), "cleat_cfg_#{System.unique_integer([:positive])}.json")
    previous = Map.new(@isolated_env, &{&1, System.get_env(&1)})

    System.put_env("CLEAT_CONFIG", path)
    Enum.each(~w(CLEAT_BASE_DOMAIN CLEAT_SITES_BASE_DOMAIN), &System.delete_env/1)

    on_exit(fn ->
      Application.delete_env(:cleat_cli, :req_plug)
      Enum.each(previous, fn {key, value} -> restore_env(key, value) end)
      File.rm(path)
    end)

    :ok
  end

  test "triggers a deploy and reports success" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert ["Bearer tok"] = Plug.Conn.get_req_header(conn, "authorization")
      assert conn.request_path == "/api/v1/apps/my-app/deployments"

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"data" => %{"id" => 7, "status" => "queued"}})
    end)

    assert :ok = Deploy.run("my-app", %{panel: "https://panel.test", token: "tok"})
  end

  test "surfaces API errors" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(404)
      |> Req.Test.json(%{"error" => "not_found"})
    end)

    assert {:error, message} = Deploy.run("missing", %{panel: "https://panel.test", token: "tok"})
    assert message =~ "Not found"
  end

  test "deploys a repo that is already registered" do
    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{
            "data" => [%{"slug" => "trip-planner", "github_repo" => "owner/repo"}]
          })

        {"POST", "/api/v1/apps/trip-planner/deployments"} ->
          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 9, "status" => "queued"}})
      end
    end)

    assert :ok =
             Deploy.run(nil, %{panel: "https://panel.test", token: "tok", repo: "owner/repo"})
  end

  test "registers an unknown repo when server and host are given" do
    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{"data" => []})

        {"POST", "/api/v1/apps"} ->
          body = Jason.decode!(Req.Test.raw_body(conn))
          assert body["github_repo"] == "owner/my-repo"
          assert body["server_id"] == "3"
          assert body["host"] == "my-repo.example.com"

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 11, "slug" => "my-repo"}})

        {"POST", "/api/v1/apps/my-repo/deployments"} ->
          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 12, "status" => "queued"}})
      end
    end)

    assert :ok =
             Deploy.run(nil, %{
               panel: "https://panel.test",
               token: "tok",
               repo: "owner/my-repo",
               server: "3",
               host: "my-repo.example.com"
             })
  end

  test "registers an unknown repo using the detected runtime" do
    dir = tmp_project(~s({"dependencies":{"@tanstack/react-start":"^1.0.0"}}))
    on_exit(fn -> File.rm_rf(dir) end)

    parent = Path.dirname(dir)
    original = File.cwd!()

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{"data" => []})

        {"POST", "/api/v1/apps"} ->
          body = Jason.decode!(Req.Test.raw_body(conn))
          assert body["runtime"] == "node"

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 30, "slug" => "lumina"}})

        {"POST", "/api/v1/apps/lumina/deployments"} ->
          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 31, "status" => "queued"}})
      end
    end)

    File.cd!(dir)

    assert :ok =
             Deploy.run(nil, %{
               panel: "https://panel.test",
               token: "tok",
               repo: "owner/lumina",
               server: "3",
               host: "lumina.example.com"
             })

    File.cd!(original)
    assert File.dir?(parent)
  end

  test "an explicit --runtime wins over detection" do
    dir = tmp_project(~s({"dependencies":{"@tanstack/react-start":"^1.0.0"}}))
    on_exit(fn -> File.rm_rf(dir) end)
    original = File.cwd!()

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{"data" => []})

        {"POST", "/api/v1/apps"} ->
          assert Jason.decode!(Req.Test.raw_body(conn))["runtime"] == "phoenix"

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 40, "slug" => "lumina"}})

        {"POST", "/api/v1/apps/lumina/deployments"} ->
          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 41, "status" => "queued"}})
      end
    end)

    File.cd!(dir)

    assert :ok =
             Deploy.run(nil, %{
               panel: "https://panel.test",
               token: "tok",
               repo: "owner/lumina",
               server: "3",
               host: "lumina.example.com",
               runtime: "phoenix"
             })

    File.cd!(original)
  end

  test "rejects an unknown repo whose slug collides with an existing app" do
    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{
            "data" => [%{"slug" => "minha-loja", "github_repo" => "someone/else"}]
          })

        other ->
          flunk("unexpected request: #{inspect(other)}")
      end
    end)

    assert {:error, message} =
             Deploy.run(nil, %{
               panel: "https://panel.test",
               token: "tok",
               repo: "owner/minha-loja",
               server: "5",
               host: "x.example.com"
             })

    assert message =~ "already exists"
  end

  test "strips a .git suffix when deriving the slug" do
    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{"data" => []})

        {"POST", "/api/v1/apps"} ->
          body = Jason.decode!(Req.Test.raw_body(conn))
          assert body["github_repo"] == "owner/my-repo.git"
          assert body["slug"] == "my-repo"

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 80, "slug" => "my-repo"}})

        {"POST", "/api/v1/apps/my-repo/deployments"} ->
          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 81, "status" => "queued"}})
      end
    end)

    assert :ok =
             Deploy.run(nil, %{
               panel: "https://panel.test",
               token: "tok",
               repo: "owner/my-repo.git",
               server: "3",
               host: "my-repo.example.com"
             })
  end

  test "errors when a static repo has no host and no sites base domain" do
    dir = tmp_static_project()
    original = File.cwd!()
    on_exit(fn -> File.cd!(original) end)
    on_exit(fn -> File.rm_rf(dir) end)
    File.cd!(dir)

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{"data" => []})

        other ->
          flunk("unexpected request: #{inspect(other)}")
      end
    end)

    assert {:error, message} =
             Deploy.run(nil, %{
               panel: "https://panel.test",
               token: "tok",
               repo: "owner/minha-loja",
               server: "5"
             })

    File.cd!(original)
    assert message =~ "sites_base_domain"
  end

  test "an explicit --host wins over static detection" do
    dir = tmp_static_project()
    original = File.cwd!()
    on_exit(fn -> File.cd!(original) end)
    on_exit(fn -> File.rm_rf(dir) end)

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{"data" => []})

        {"POST", "/api/v1/apps"} ->
          assert Jason.decode!(Req.Test.raw_body(conn))["host"] == "explicit.example.com"

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 90, "slug" => "minha-loja"}})

        {"POST", "/api/v1/apps/minha-loja/deployments"} ->
          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 91, "status" => "queued"}})
      end
    end)

    File.cd!(dir)

    assert :ok =
             Deploy.run(nil, %{
               panel: "https://panel.test",
               token: "tok",
               repo: "owner/minha-loja",
               server: "5",
               host: "ExPlicit.Example.COM"
             })

    File.cd!(original)
  end

  test "derives a sites host for a static repo when no host is given" do
    dir =
      Path.join(System.tmp_dir!(), "cleat-deploy-static-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    original = File.cwd!()

    on_exit(fn ->
      File.cd!(original)
      File.rm_rf(dir)
    end)

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{"data" => []})

        {"POST", "/api/v1/apps"} ->
          body = Jason.decode!(Req.Test.raw_body(conn))
          assert body["host"] == "minha-loja.sites.example.com"
          assert body["runtime"] == "static"

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 70, "slug" => "minha-loja"}})

        {"POST", "/api/v1/apps/minha-loja/deployments"} ->
          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 71, "status" => "queued"}})
      end
    end)

    File.cd!(dir)

    assert :ok =
             Deploy.run(nil, %{
               panel: "https://panel.test",
               token: "tok",
               repo: "owner/minha-loja",
               server: "5",
               sites_base_domain: "sites.example.com"
             })
  end

  defp tmp_project(package_json) do
    dir =
      Path.join(System.tmp_dir!(), "cleat-deploy-proj-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "package.json"), package_json)
    dir
  end

  defp tmp_static_project do
    dir =
      Path.join(System.tmp_dir!(), "cleat-deploy-static-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    dir
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  test "streams the build log while watching" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Req.Test.stub(__MODULE__, fn conn ->
      n = Agent.get_and_update(counter, fn n -> {n, n + 1} end)

      {status, log} =
        case n do
          0 -> {"running", "step 1\n"}
          1 -> {"running", "step 1\nstep 2\n"}
          _ -> {"success", "step 1\nstep 2\nstep 3\n"}
        end

      Req.Test.json(conn, %{"data" => %{"id" => 1, "status" => status, "log" => log}})
    end)

    output =
      capture_io(fn ->
        assert :ok =
                 Deploy.watch(Cleat.Client.new("https://panel.test", "tok"), 1, interval: 1)
      end)

    assert output =~ "step 1"
    assert output =~ "step 2"
    assert output =~ "step 3"
    refute output =~ "step 1\nstep 1"
  end

  test "asks for a server when the repo is unknown" do
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"data" => []}) end)

    assert {:error, message} =
             Deploy.run(nil, %{panel: "https://panel.test", token: "tok", repo: "owner/repo"})

    assert message =~ "--server"
  end
end
