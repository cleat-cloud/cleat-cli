defmodule Cleat.MCP.Tools.Identity do
  @moduledoc false

  alias Cleat.Client
  alias Cleat.MCP.Tools.{Schema, Support}

  @doc false
  def tools do
    [
      %{
        "name" => "whoami",
        "description" => "Show the authenticated user and tenant",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{"panel" => Schema.panel(), "token" => Schema.token()}
        },
        "handler" => fn args ->
          Support.with_client(args, fn client ->
            with {:ok, body} <- Client.me(client), do: {:ok, Support.data_text(body)}
          end)
        end
      }
    ]
  end
end
