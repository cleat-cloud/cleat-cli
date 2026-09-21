defmodule Cleat.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias Cleat.MCP.Server

  test "handles initialize" do
    request = %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}}
    response = Server.handle(request)

    assert %{"id" => 1, "result" => result} = response
    assert result["serverInfo"]["name"] == "cleat"
    assert result["capabilities"] == %{"tools" => %{}}
    assert is_binary(result["protocolVersion"])
  end

  test "lists tools" do
    request = %{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"}
    assert %{"result" => %{"tools" => tools}} = Server.handle(request)
    assert Enum.any?(tools, &(&1["name"] == "deploy"))
  end

  test "calls a tool and wraps the result as text content" do
    Application.put_env(:cleat_cli, :req_plug, {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:cleat_cli, :req_plug) end)

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"data" => [%{"slug" => "lumina", "runtime" => "node"}]})
    end)

    request = %{
      "jsonrpc" => "2.0",
      "id" => 3,
      "method" => "tools/call",
      "params" => %{
        "name" => "apps_list",
        "arguments" => %{"panel" => "https://panel.test", "token" => "tok"}
      }
    }

    assert %{"result" => %{"isError" => false, "content" => [%{"text" => text}]}} =
             Server.handle(request)

    assert Jason.decode!(text) |> hd() |> Map.get("slug") == "lumina"
  end

  test "turns a tool error into an isError result" do
    request = %{
      "jsonrpc" => "2.0",
      "id" => 4,
      "method" => "tools/call",
      "params" => %{"name" => "apps_show", "arguments" => %{}}
    }

    assert %{"result" => %{"isError" => true}} = Server.handle(request)
  end

  test "unknown method is an error response" do
    request = %{"jsonrpc" => "2.0", "id" => 5, "method" => "nope"}
    assert %{"error" => %{"code" => -32601}} = Server.handle(request)
  end

  test "a notification produces no response" do
    request = %{"jsonrpc" => "2.0", "method" => "notifications/initialized"}
    assert Server.handle(request) == :noreply
  end
end
