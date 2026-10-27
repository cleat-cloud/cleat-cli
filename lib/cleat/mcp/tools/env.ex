defmodule Cleat.MCP.Tools.Env do
  @moduledoc false

  alias Cleat.Client
  alias Cleat.MCP.Tools.{Schema, Support}

  @doc false
  def tools do
    [
      %{
        "name" => "env_list",
        "description" =>
          "List env vars (secrets masked unless reveal is true); branch filters the vars that apply to it",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "app" => Schema.app(),
            "branch" => %{
              "type" => "string",
              "description" => "Only vars that apply to this branch (all branches + this one)"
            },
            "reveal" => %{"type" => "boolean"},
            "panel" => Schema.panel(),
            "token" => Schema.token()
          },
          "required" => ["app"]
        },
        "handler" => fn args ->
          Support.with_client(args, fn client ->
            with {:ok, body} <-
                   Client.list_env(client, args["app"], args["reveal"] == true, args["branch"]),
                 do: {:ok, Support.data_text(body)}
          end)
        end
      },
      %{
        "name" => "env_set",
        "description" =>
          "Upsert env vars on an app, optionally scoped to one branch (default: all branches)",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "app" => Schema.app(),
            "vars" => %{"type" => "object", "additionalProperties" => %{"type" => "string"}},
            "branch" => %{
              "type" => "string",
              "description" => "Branch the vars are scoped to; omit for all branches"
            },
            "panel" => Schema.panel(),
            "token" => Schema.token()
          },
          "required" => ["app", "vars"]
        },
        "handler" => fn args ->
          Support.with_client(args, fn client ->
            attrs =
              case args["branch"] do
                branch when branch in [nil, ""] -> %{vars: args["vars"]}
                branch -> %{vars: args["vars"], branch: branch}
              end

            with {:ok, body} <- Client.set_env(client, args["app"], attrs),
                 do: {:ok, Support.data_text(body)}
          end)
        end
      },
      %{
        "name" => "env_unset",
        "description" =>
          "Delete an env var from an app, optionally scoped to one branch (default: all branches)",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "app" => Schema.app(),
            "key" => %{"type" => "string"},
            "branch" => %{
              "type" => "string",
              "description" => "Branch scope of the var; omit for all branches"
            },
            "panel" => Schema.panel(),
            "token" => Schema.token()
          },
          "required" => ["app", "key"]
        },
        "handler" => fn args ->
          Support.with_client(args, fn client ->
            with {:ok, body} <-
                   Client.delete_env(client, args["app"], args["key"], args["branch"]),
                 do: {:ok, Support.data_text(body)}
          end)
        end
      }
    ]
  end
end
