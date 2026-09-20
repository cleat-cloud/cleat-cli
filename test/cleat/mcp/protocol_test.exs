defmodule Cleat.MCP.ProtocolTest do
  use ExUnit.Case, async: true

  alias Cleat.MCP.Protocol

  describe "decode/1" do
    test "decodes a request line" do
      assert {:ok, %{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"}} =
               Protocol.decode(~s({"jsonrpc":"2.0","id":1,"method":"ping"}))
    end

    test "decodes a notification (no id)" do
      assert {:ok, %{"method" => "notifications/initialized"}} =
               Protocol.decode(~s({"jsonrpc":"2.0","method":"notifications/initialized"}))
    end

    test "rejects invalid JSON" do
      assert {:error, :parse_error} = Protocol.decode("{not json")
    end

    test "rejects a non-object" do
      assert {:error, :invalid_request} = Protocol.decode("[1,2]")
    end
  end

  describe "response/3 and error/3" do
    test "builds a result response with the id" do
      assert %{"jsonrpc" => "2.0", "id" => 7, "result" => %{"ok" => true}} =
               Protocol.response(7, %{"ok" => true})
    end

    test "builds an error response" do
      assert %{"jsonrpc" => "2.0", "id" => 7, "error" => %{"code" => -32601, "message" => "no"}} =
               Protocol.error(7, -32601, "no")
    end
  end

  describe "tool_result/2" do
    test "wraps text content" do
      assert %{"content" => [%{"type" => "text", "text" => "hi"}], "isError" => false} =
               Protocol.tool_result("hi")
    end

    test "marks errors" do
      assert %{"content" => [%{"type" => "text", "text" => "boom"}], "isError" => true} =
               Protocol.tool_result("boom", error: true)
    end
  end

  describe "encode/1" do
    test "encodes to a single JSON line" do
      line = Protocol.encode(%{"jsonrpc" => "2.0", "id" => 1, "result" => %{}})
      assert is_binary(line)
      refute String.contains?(line, "\n")
      assert Jason.decode!(line) == %{"jsonrpc" => "2.0", "id" => 1, "result" => %{}}
    end
  end
end
