defmodule Cleat.MCP.Tools do
  @moduledoc """
  Static registry of MCP tools exposed by `cleat mcp`.

  Each tool declares a name, description, JSON Schema and a handler that reuses
  `Cleat.Client`/`Cleat.Commands`. Handlers return `{:ok, json_string}` or
  `{:error, message}`; the server turns errors into `isError` tool results.

  The definitions live in one module per domain under `Cleat.MCP.Tools.*`; this
  module only aggregates them in a stable order and dispatches calls.
  """

  alias Cleat.MCP.Tools.{
    Apps,
    Deployments,
    Env,
    Identity,
    Observability,
    Servers,
    Sites,
    Support
  }

  @domains [Identity, Servers, Observability, Apps, Env, Deployments, Sites]

  def list, do: Enum.map(tools(), &Map.take(&1, ["name", "description", "inputSchema"]))

  def call(name, args) when is_map(args) do
    try do
      case Enum.find(tools(), &(&1["name"] == name)) do
        nil ->
          {:error, "unknown tool: #{name}"}

        tool ->
          with :ok <- validate(tool, args) do
            tool["handler"].(args)
          end
      end
    rescue
      error -> {:error, Exception.message(error)}
    end
  end

  def call(_name, _args), do: {:error, "invalid arguments"}

  defp validate(tool, args) do
    missing =
      tool["inputSchema"]["required"]
      |> Kernel.||([])
      |> Enum.reject(&Support.present?(args, &1))

    case missing do
      [] -> :ok
      fields -> {:error, "missing required argument(s): #{Enum.join(fields, ", ")}"}
    end
  end

  defp tools, do: Enum.flat_map(@domains, & &1.tools())
end
