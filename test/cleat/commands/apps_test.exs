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
