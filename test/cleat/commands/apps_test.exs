defmodule Cleat.Commands.AppsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Cleat.Commands.Apps

  @conn %{panel: "https://panel.test", token: "tok"}

  setup do
    Application.put_env(:cleat_cli, :req_plug, {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:cleat_cli, :req_plug) end)
    :ok
  end

  test "updates branch and auto-deploy" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "PATCH"
      assert conn.request_path == "/api/v1/apps/my-app"

      assert Jason.decode!(Req.Test.raw_body(conn)) ==
               %{"branch" => "develop", "auto_deploy" => false}

      Req.Test.json(conn, %{
        "data" => %{"slug" => "my-app", "branch" => "develop", "auto_deploy" => false}
      })
    end)

    assert :ok =
             Apps.run(
               ["update", "my-app"],
               Map.put(@conn, :branch, "develop") |> Map.put(:auto_deploy, false)
             )
  end

  test "updates the host" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "PATCH"
      assert Jason.decode!(Req.Test.raw_body(conn)) == %{"host" => "new.example.com"}

      Req.Test.json(conn, %{
        "data" => %{
          "slug" => "my-app",
          "branch" => "main",
          "auto_deploy" => true,
          "host" => "new.example.com"
        }
      })
    end)

    assert :ok = Apps.run(["update", "my-app"], Map.put(@conn, :host, "New.Example.com"))
  end

  test "updates the port" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "PATCH"
      assert Jason.decode!(Req.Test.raw_body(conn)) == %{"port" => 4030}

      Req.Test.json(conn, %{
        "data" => %{
          "slug" => "my-app",
          "branch" => "main",
          "auto_deploy" => true,
          "host" => "my-app.example.com",
          "port" => 4030
        }
      })
    end)

    assert :ok = Apps.run(["update", "my-app"], Map.put(@conn, :port, 4030))
  end

  test "updates the repo" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "PATCH"
      assert Jason.decode!(Req.Test.raw_body(conn)) == %{"github_repo" => "owner/new"}

      Req.Test.json(conn, %{
        "data" => %{
          "slug" => "my-app",
          "github_repo" => "owner/new",
          "branch" => "main",
          "auto_deploy" => true,
          "host" => "my-app.example.com",
          "port" => 4000
        }
      })
    end)

    assert :ok = Apps.run(["update", "my-app"], Map.put(@conn, :repo, "owner/new"))
  end

  test "updates indexable" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "PATCH"
      assert Jason.decode!(Req.Test.raw_body(conn)) == %{"indexable" => true}

      Req.Test.json(conn, %{
        "data" => %{
          "slug" => "my-app",
          "indexable" => true,
          "branch" => "main",
          "auto_deploy" => true,
          "host" => "my-app.example.com",
          "port" => 4000,
          "runtime" => "static"
        }
      })
    end)

    assert :ok = Apps.run(["update", "my-app"], Map.put(@conn, :indexable, true))
  end

  test "updates the runtime" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "PATCH"
      assert Jason.decode!(Req.Test.raw_body(conn)) == %{"runtime" => "node"}

      Req.Test.json(conn, %{
        "data" => %{
          "slug" => "my-app",
          "runtime" => "node",
          "branch" => "main",
          "auto_deploy" => true,
          "host" => "my-app.example.com",
          "port" => 4000
        }
      })
    end)

    assert :ok = Apps.run(["update", "my-app"], Map.put(@conn, :runtime, "node"))
  end

  test "updates runtime_apt_packages from --apt" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "PATCH"

      assert Jason.decode!(Req.Test.raw_body(conn)) == %{
               "runtime_apt_packages" => ["ffmpeg", "webp"]
             }

      Req.Test.json(conn, %{
        "data" => %{
          "slug" => "my-app",
          "runtime_apt_packages" => ["ffmpeg", "webp"],
          "github_repo" => "owner/app",
          "branch" => "main",
          "auto_deploy" => true,
          "indexable" => false,
          "host" => "my-app.example.com",
          "port" => 4000,
          "runtime" => "node"
        }
      })
    end)

    assert :ok = Apps.run(["update", "my-app"], Map.put(@conn, :apt, "ffmpeg,webp"))
  end

  test "creates an app with --apt packages" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert Jason.decode!(Req.Test.raw_body(conn))["runtime_apt_packages"] == ["ffmpeg", "webp"]

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"data" => %{"id" => 9, "slug" => "gowa"}})
    end)

    assert :ok =
             Apps.run(
               ["create"],
               %{
                 panel: "https://panel.test",
                 token: "tok",
                 name: "gowa",
                 repo: "owner/gowa",
                 host: "gowa.example.com",
                 server: "5",
                 apt: "ffmpeg, webp"
               }
             )
  end

  test "creates an app using the detected runtime" do
    dir =
      Path.join(System.tmp_dir!(), "cleat-apps-proj-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "package.json"), ~s({"dependencies":{"next":"15.0.0"}}))
    original = File.cwd!()

    on_exit(fn ->
      File.cd!(original)
      File.rm_rf(dir)
    end)

    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert Jason.decode!(Req.Test.raw_body(conn))["runtime"] == "node"

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"data" => %{"id" => 55, "slug" => "lumina"}})
    end)

    File.cd!(dir)

    assert :ok =
             Apps.run(
               ["create"],
               %{
                 panel: "https://panel.test",
                 token: "tok",
                 name: "Lumina",
                 repo: "owner/lumina",
                 host: "lumina.example.com",
                 server: "3"
               }
             )
  end

  test "deletes an app with --yes" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "DELETE"
      assert conn.request_path == "/api/v1/apps/my-app"
      Plug.Conn.send_resp(conn, 204, "")
    end)

    assert :ok = Apps.run(["delete", "my-app"], Map.put(@conn, :yes, true))
  end

  test "refuses to delete without --yes" do
    assert {:error, message} = Apps.run(["delete", "my-app"], @conn)
    assert message =~ "--yes"
  end

  test "prints runtime logs" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/v1/apps/my-app/logs"

      Req.Test.json(conn, %{
        "data" => %{
          "unit" => "phx-my-app",
          "lines" => ["line a", "line b"],
          "fetched_at" => "2026-09-19T12:00:00Z"
        }
      })
    end)

    output = capture_io(fn -> assert :ok = Apps.run(["logs", "my-app"], @conn) end)

    assert output =~ "line a"
    assert output =~ "line b"
  end

  test "passes log filters as query params" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/v1/apps/my-app/logs"
      assert conn.query_string == "grep=error&since=1h&tail=50"

      Req.Test.json(conn, %{
        "data" => %{"unit" => "phx-my-app", "lines" => ["boom"], "fetched_at" => "t"}
      })
    end)

    opts =
      @conn
      |> Map.put(:since, "1h")
      |> Map.put(:tail, 50)
      |> Map.put(:grep, "error")

    output = capture_io(fn -> assert :ok = Apps.run(["logs", "my-app"], opts) end)

    assert output =~ "boom"
  end

  test "follows runtime logs and prints only new lines" do
    Application.put_env(:cleat_cli, :logs_follow_interval_ms, 0)
    Application.put_env(:cleat_cli, :logs_follow_max_polls, 1)

    on_exit(fn ->
      Application.delete_env(:cleat_cli, :logs_follow_interval_ms)
      Application.delete_env(:cleat_cli, :logs_follow_max_polls)
    end)

    counter = :counters.new(1, [])

    Req.Test.stub(__MODULE__, fn conn ->
      :counters.add(counter, 1, 1)
      n = :counters.get(counter, 1)

      lines = if n == 1, do: ["alpha", "beta"], else: ["beta", "gamma"]

      Req.Test.json(conn, %{
        "data" => %{"unit" => "phx-my-app", "lines" => lines, "fetched_at" => "t"}
      })
    end)

    output =
      capture_io(fn ->
        assert :ok = Apps.run(["logs", "my-app"], Map.put(@conn, :follow, true))
      end)

    assert output =~ "alpha"
    assert output =~ "gamma"
    assert length(String.split(output, "beta")) == 2
  end

  test "requires at least one field to update" do
    assert {:error, message} = Apps.run(["update", "my-app"], @conn)
    assert message =~ "nothing to update"
  end

  test "create rejects a request missing required options" do
    assert {:error, message} = Apps.run(["create"], @conn)
    assert message =~ "--repo"
    assert message =~ "--server"
  end
end
