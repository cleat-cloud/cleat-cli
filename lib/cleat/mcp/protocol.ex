defmodule Cleat.MCP.Protocol do
  @moduledoc """
  Minimal JSON-RPC 2.0 codec for the MCP stdio transport.

  The MCP stdio transport is newline-delimited: one JSON object per line on
  stdin/stdout. This module only knows how to decode a line and shape the
  responses; transport concerns live in `Cleat.MCP.Server`.
  """

  @jsonrpc "2.0"

  @doc "Decodes one line into a request/notification map."
  def decode(line) when is_binary(line) do
    case Jason.decode(line) do
      {:ok, %{} = message} ->
        case Map.fetch(message, "jsonrpc") do
          :error -> {:ok, Map.put(message, "jsonrpc", @jsonrpc)}
          {:ok, @jsonrpc} -> {:ok, message}
          {:ok, _other} -> {:error, :invalid_request}
        end

      {:ok, _other} ->
        {:error, :invalid_request}

      {:error, _} ->
        {:error, :parse_error}
    end
  end

  @doc "Builds a success response."
  def response(id, result) do
    %{"jsonrpc" => @jsonrpc, "id" => id, "result" => result}
  end

  @doc "Builds an error response."
  def error(id, code, message) do
    %{"jsonrpc" => @jsonrpc, "id" => id, "error" => %{"code" => code, "message" => message}}
  end

  @doc "Wraps tool output as MCP tool content."
  def tool_result(text, opts \\ []) when is_binary(text) do
    %{
      "content" => [%{"type" => "text", "text" => text}],
      "isError" => Keyword.get(opts, :error, false)
    }
  end

  @doc "Encodes a message as a single line (no trailing newline)."
  def encode(message) when is_map(message), do: Jason.encode!(message)
end
