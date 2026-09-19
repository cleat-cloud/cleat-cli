defmodule Cleat.Commands.DeployTest do
  use ExUnit.Case, async: false

  alias Cleat.Commands.Deploy

  setup do
    Application.put_env(:cleat_cli, :req_plug, {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:cleat_cli, :req_plug) end)
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

  test "asks for a server when the repo is unknown" do
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"data" => []}) end)

    assert {:error, message} =
             Deploy.run(nil, %{panel: "https://panel.test", token: "tok", repo: "owner/repo"})

    assert message =~ "--server"
  end
end
