defmodule Cleat.MCP.Server do
  @moduledoc """
  MCP stdio server for `cleat mcp`.

  Reads newline-delimited JSON-RPC from stdin and writes responses to stdout.
  `handle/1` is the pure dispatcher (unit-tested); `run/1` wires it to stdio.
  """

  alias Cleat.MCP.{Protocol, Tools}

  @protocol_version "2025-06-18"
  @name "cleat"
  @version Mix.Project.config()[:version] || "0.0.0"

  @doc "Dispatches one decoded request. Returns a response map or `:noreply`."
  def handle(%{"method" => method} = request) when is_binary(method) do
    id = Map.get(request, "id")
    params = Map.get(request, "params", %{})

    cond do
      is_nil(id) -> :noreply
      method == "initialize" -> Protocol.response(id, initialize_result())
      method == "tools/list" -> Protocol.response(id, %{"tools" => Tools.list()})
      method == "tools/call" -> call_tool(id, params)
      method == "ping" -> Protocol.response(id, %{})
      true -> Protocol.error(id, -32601, "method not found: #{method}")
    end
  end

  def handle(%{"id" => nil}), do: :noreply
  def handle(%{"id" => id}), do: Protocol.error(id, -32600, "invalid request")
  def handle(_), do: :noreply

  defp initialize_result do
    %{
      "protocolVersion" => @protocol_version,
      "capabilities" => %{"tools" => %{}},
      "serverInfo" => %{"name" => @name, "version" => @version}
    }
  end

  defp call_tool(id, %{"name" => name, "arguments" => args}) when is_map(args) do
    run_tool(id, name, args)
  end

  defp call_tool(id, %{"name" => _name, "arguments" => _invalid}) do
    Protocol.error(id, -32602, "invalid params")
  end

  defp call_tool(id, %{"name" => name}) do
    run_tool(id, name, %{})
  end

  defp call_tool(id, _params), do: Protocol.error(id, -32602, "invalid params")

  defp run_tool(id, name, args) do
    case Tools.call(name, args) do
      {:ok, text} -> Protocol.response(id, Protocol.tool_result(text))
      {:error, message} -> Protocol.response(id, Protocol.tool_result(message, error: true))
    end
  end

  @doc "Runs the stdio loop until stdin reaches EOF."
  def run(opts \\ []) do
    input = Keyword.get(opts, :input, :stdio)
    output = Keyword.get(opts, :output, :stdio)

    loop(input, output)
  end

  defp loop(input, output) do
    case IO.read(input, :line) do
      :eof ->
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "cleat mcp: #{inspect(reason)}")
        :ok

      line ->
        line
        |> String.trim_trailing("\n")
        |> String.trim_trailing("\r")
        |> respond(output)

        loop(input, output)
    end
  end

  defp respond("", _output), do: :ok

  defp respond(line, output) do
    try do
      dispatch(line, output)
    rescue
      error ->
        IO.puts(output, Protocol.encode(Protocol.error(nil, -32603, Exception.message(error))))
    end
  end

  defp dispatch(line, output) do
    case Protocol.decode(line) do
      {:ok, request} ->
        case handle(request) do
          :noreply -> :ok
          response -> IO.puts(output, Protocol.encode(response))
        end

      {:error, :parse_error} ->
        IO.puts(output, Protocol.encode(Protocol.error(nil, -32700, "parse error")))

      {:error, :invalid_request} ->
        IO.puts(output, Protocol.encode(Protocol.error(nil, -32600, "invalid request")))
    end
  end
end
