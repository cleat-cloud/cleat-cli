defmodule Cleat.MCP.Tools.Deployments do
  @moduledoc false

  alias Cleat.Client
  alias Cleat.MCP.Tools.{Schema, Support}

  @doc false
  def tools do
    [
      %{
        "name" => "deploy",
        "description" => "Queue a deploy and return the deployment id (does not wait)",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "app" => Schema.app(),
            "ref" => %{"type" => "string"},
            "panel" => Schema.panel(),
            "token" => Schema.token()
          },
          "required" => ["app"]
        },
        "handler" => fn args ->
          Support.with_client(args, fn client ->
            with {:ok, body} <-
                   Client.create_deployment(client, args["app"], %{git_ref: args["ref"]}),
                 do: {:ok, Support.data_text(body)}
          end)
        end
      },
      %{
        "name" => "deploy_status",
        "description" => "List recent deployments for an app",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "app" => Schema.app(),
            "panel" => Schema.panel(),
            "token" => Schema.token()
          },
          "required" => ["app"]
        },
        "handler" => fn args ->
          Support.with_client(args, fn client ->
            with {:ok, body} <- Client.list_deployments(client, args["app"]),
                 do: {:ok, Support.data_text(body)}
          end)
        end
      },
      %{
        "name" => "deploy_logs",
        "description" => "Build log of a deployment",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => "integer"},
            "panel" => Schema.panel(),
            "token" => Schema.token()
          },
          "required" => ["id"]
        },
        "handler" => fn args ->
          Support.with_client(args, fn client ->
            with {:ok, body} <- Client.get_deployment(client, args["id"]),
                 do: {:ok, Support.data_text(body)}
          end)
        end
      },
      %{
        "name" => "cancel_deploy",
        "description" => "Cancel the active deploy of an app",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "app" => Schema.app(),
            "panel" => Schema.panel(),
            "token" => Schema.token()
          },
          "required" => ["app"]
        },
        "handler" => fn args ->
          Support.with_client(args, fn client ->
            with {:ok, body} <- Client.cancel_deploy(client, args["app"]),
                 do: {:ok, Support.data_text(body)}
          end)
        end
      }
    ]
  end
end
