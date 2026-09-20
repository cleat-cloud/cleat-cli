defmodule Cleat.MCP.ToolsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Cleat.MCP.Tools

  setup do
    Application.put_env(:cleat_cli, :req_plug, {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:cleat_cli, :req_plug) end)
    :ok
  end

  test "lists every expected tool" do
    names = Tools.list() |> Enum.map(& &1["name"])

    assert names == [
             "whoami",
             "servers_list",
             "apps_list",
             "apps_show",
             "apps_create",
             "apps_update",
             "apps_logs",
             "env_list",
             "env_set",
             "env_unset",
             "deploy",
             "deploy_status",
             "deploy_logs",
             "cancel_deploy",
             "drop",
             "init_project"
           ]
  end

  test "every tool exposes a JSON schema object" do
    for tool <- Tools.list() do
      assert %{"type" => "object"} = tool["inputSchema"]
      assert is_binary(tool["description"])
    end
  end

  test "call/2 dispatches to the handler and returns a text result" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/me"
      Req.Test.json(conn, %{"data" => %{"email" => "me@example.com"}})
    end)

    assert {:ok, text} =
             Tools.call("whoami", %{"panel" => "https://panel.test", "token" => "tok"})

    assert is_binary(text)
    assert Jason.decode!(text)["email"] == "me@example.com"
  end

  test "call/2 reports an unknown tool" do
    assert {:error, message} = Tools.call("nope", %{})
    assert message =~ "unknown tool"
  end

  test "call/2 validates required arguments" do
    assert {:error, message} = Tools.call("apps_show", %{})
    assert message =~ "app"
  end

  test "call/2 rejects non-map arguments" do
    assert {:error, "invalid arguments"} = Tools.call("whoami", [])
  end

  test "call/2 converts handler exceptions into errors" do
    assert {:error, message} = Tools.call("whoami", %{"panel" => 123, "token" => "tok"})
    assert is_binary(message)
  end

  test "call/2 surfaces a client error from a non-2xx response" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(404)
      |> Req.Test.json(%{"error" => "not_found"})
    end)

    assert {:error, message} =
             Tools.call("apps_show", %{
               "app" => "x",
               "panel" => "https://panel.test",
               "token" => "tok"
             })

    assert message =~ "Not found"
  end

  test "apps_update with an empty update returns an actionable error" do
    assert {:error, message} = Tools.call("apps_update", %{"app" => "my-app"})
    assert message =~ "nothing to update"
  end

  test "init_project does not write to stdout" do
    dir =
      Path.join(System.tmp_dir!(), "cleat-mcp-init-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    original = File.cwd!()
    File.cd!(dir)

    on_exit(fn ->
      File.cd!(original)
      File.rm_rf(dir)
    end)

    output =
      capture_io(fn ->
        assert {:ok, text} = Tools.call("init_project", %{"overwrite" => true})
        assert Jason.decode!(text)["created"] == ".cleat_deploy/deploy.json"
      end)

    assert output == ""
  end
end
