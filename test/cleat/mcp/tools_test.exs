defmodule Cleat.MCP.ToolsTest do
  use ExUnit.Case, async: false

  alias Cleat.MCP.Tools

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
    Application.put_env(:cleat_cli, :req_plug, {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:cleat_cli, :req_plug) end)

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
end
