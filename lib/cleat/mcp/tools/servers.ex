defmodule Cleat.MCP.Tools.Servers do
  @moduledoc false

  alias Cleat.Client
  alias Cleat.MCP.Tools.{Schema, Support}

  @doc false
  def tools do
    [
      %{
        "name" => "servers_list",
        "description" => "List registered servers",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{"panel" => Schema.panel(), "token" => Schema.token()}
        },
        "handler" => fn args ->
          Support.with_client(args, fn client ->
            with {:ok, body} <- Client.list_servers(client), do: {:ok, Support.data_text(body)}
          end)
        end
      },
      %{
        "name" => "server_logs",
        "description" => "Host system journal for a server (all units, or one with unit)",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "server" => %{"type" => "string", "description" => "Server id"},
            "unit" => %{"type" => "string"},
            "tail" => %{"type" => "integer"},
            "since" => %{"type" => "string"},
            "grep" => %{"type" => "string"},
            "panel" => Schema.panel(),
            "token" => Schema.token()
          },
          "required" => ["server"]
        },
        "handler" => fn args ->
          Support.with_client(args, fn client ->
            with {:ok, body} <-
                   Client.server_logs(client, args["server"], %{
                     unit: args["unit"],
                     tail: args["tail"],
                     since: args["since"],
                     grep: args["grep"]
                   }),
                 do: {:ok, Support.data_text(body)}
          end)
        end
      }
    ]
  end
end
