defmodule Cleat.MCP.ServerTest do
  use ExUnit.Case, async: false

  alias Cleat.MCP.Server

  test "handles initialize" do
    request = %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}}
    response = Server.handle(request)

    assert %{"id" => 1, "result" => result} = response
    assert result["serverInfo"]["name"] == "cleat"
    assert result["capabilities"] == %{"tools" => %{}}
    assert result["protocolVersion"] == "2025-06-18"
    assert result["serverInfo"]["version"] == Mix.Project.config()[:version]
  end

  test "initialize echoes a client protocolVersion" do
    request = %{
      "jsonrpc" => "2.0",
      "id" => 20,
      "method" => "initialize",
      "params" => %{"protocolVersion" => "2024-11-05"}
    }

    assert %{"result" => result} = Server.handle(request)
    assert result["protocolVersion"] == "2024-11-05"
  end

  test "initialize defaults protocolVersion when the client sends none" do
    request = %{"jsonrpc" => "2.0", "id" => 21, "method" => "initialize", "params" => %{}}
    assert %{"result" => result} = Server.handle(request)
    assert result["protocolVersion"] == "2025-06-18"
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

  test "calls a tool with no arguments" do
    request = %{
      "jsonrpc" => "2.0",
      "id" => 10,
      "method" => "tools/call",
      "params" => %{"name" => "apps_show"}
    }

    assert %{"result" => %{"isError" => true}} = Server.handle(request)
  end

  test "rejects non-map arguments" do
    request = %{
      "jsonrpc" => "2.0",
      "id" => 11,
      "method" => "tools/call",
      "params" => %{"name" => "whoami", "arguments" => []}
    }

    assert %{"error" => %{"code" => -32602}} = Server.handle(request)
  end

  test "unknown method is an error response" do
    request = %{"jsonrpc" => "2.0", "id" => 5, "method" => "nope"}
    assert %{"error" => %{"code" => -32601}} = Server.handle(request)
  end

  test "handles ping" do
    request = %{"jsonrpc" => "2.0", "id" => 6, "method" => "ping"}
    assert %{"id" => 6, "result" => %{}} = Server.handle(request)
  end

  test "a non-string method is an invalid request" do
    request = %{"jsonrpc" => "2.0", "id" => 7, "method" => %{"nested" => "object"}}
    assert %{"error" => %{"code" => -32600}} = Server.handle(request)
  end

  test "a request with an id but no method is an invalid request" do
    request = %{"jsonrpc" => "2.0", "id" => 8}
    assert %{"error" => %{"code" => -32600}} = Server.handle(request)
  end

  test "a notification produces no response" do
    request = %{"jsonrpc" => "2.0", "method" => "notifications/initialized"}
    assert Server.handle(request) == :noreply
  end

  test "a null id is treated as a notification" do
    with_method = %{"jsonrpc" => "2.0", "id" => nil, "method" => "ping"}
    without_method = %{"jsonrpc" => "2.0", "id" => nil}

    assert Server.handle(with_method) == :noreply
    assert Server.handle(without_method) == :noreply
  end

  test "the stdio loop trims CRLF line endings" do
    input =
      ~s({"jsonrpc":"2.0","id":1,"method":"ping"}\r\n) <>
        "\r\n"

    output = run_loop(input)
    lines = String.split(output, "\n", trim: true)

    assert [line] = lines
    assert %{"id" => 1, "result" => %{}} = Jason.decode!(line)
  end

  test "the stdio loop keeps going after a malformed line" do
    input =
      "{not json}\n" <>
        ~s({"jsonrpc":"2.0","id":2,"method":"ping"}\n)

    output = run_loop(input)
    lines = Enum.map(String.split(output, "\n", trim: true), &Jason.decode!/1)

    assert [%{"error" => %{"code" => -32700}}, %{"id" => 2, "result" => %{}}] = lines
  end

  defp run_loop(input) do
    in_path = Path.join(System.tmp_dir!(), "cleat_mcp_in_#{System.unique_integer([:positive])}")
    out_path = Path.join(System.tmp_dir!(), "cleat_mcp_out_#{System.unique_integer([:positive])}")
    File.write!(in_path, input)

    on_exit(fn ->
      File.rm(in_path)
      File.rm(out_path)
    end)

    in_device = File.open!(in_path, [:read, :binary])
    out_device = File.open!(out_path, [:write, :binary])

    Server.run(input: in_device, output: out_device)

    File.close(in_device)
    File.close(out_device)

    File.read!(out_path)
  end
end
