defmodule Cleat.MCP.Tools.Apps do
  @moduledoc false

  alias Cleat.Client
  alias Cleat.MCP.Tools.{Schema, Support}

  @runtime_apt_packages %{
    "type" => "array",
    "items" => %{"type" => "string"},
    "description" =>
      "apt packages to install on the VM at deploy. Alternative: commit .cleat_deploy/runtime-packages (or .cleat_deploy/post-install.sh) in the repo"
  }

  @doc false
  def tools do
    [
      %{
        "name" => "apps_list",
        "description" => "List apps",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{"panel" => Schema.panel(), "token" => Schema.token()}
        },
        "handler" => fn args ->
          Support.with_client(args, fn client ->
            with {:ok, body} <- Client.list_apps(client), do: {:ok, Support.data_text(body)}
          end)
        end
      },
      %{
        "name" => "apps_show",
        "description" => "Show one app by id or slug",
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
            with {:ok, body} <- Client.get_app(client, args["app"]),
                 do: {:ok, Support.data_text(body)}
          end)
        end
      },
      %{
        "name" => "apps_create",
        "description" =>
          "Create an app. server accepts a servers_list id, name or slug. runtime_apt_packages installs apt deps on the VM; alternatively commit .cleat_deploy/runtime-packages",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "name" => %{"type" => "string"},
            "repo" => %{"type" => "string", "description" => "owner/repo"},
            "host" => %{"type" => "string"},
            "server" => %{
              "type" => "string",
              "description" => "Server id, name or slug from servers_list"
            },
            "runtime" => %{"type" => "string"},
            "slug" => %{"type" => "string"},
            "branch" => %{"type" => "string"},
            "port" => %{"type" => "integer"},
            "runtime_apt_packages" => @runtime_apt_packages,
            "panel" => Schema.panel(),
            "token" => Schema.token()
          },
          "required" => ["name", "repo", "host", "server"]
        },
        "handler" => fn args ->
          Support.with_client(args, fn client ->
            with {:ok, server_id} <- Support.resolve_server_id(client, args["server"]) do
              attrs =
                %{
                  "name" => args["name"],
                  "github_repo" => args["repo"],
                  "host" => args["host"],
                  "server_id" => server_id,
                  "slug" => args["slug"],
                  "branch" => args["branch"],
                  "port" => args["port"],
                  "runtime" => args["runtime"],
                  "runtime_apt_packages" => args["runtime_apt_packages"]
                }
                |> Map.reject(fn {_k, v} -> is_nil(v) or v == "" end)

              with {:ok, body} <- Client.create_app(client, attrs),
                   do: {:ok, Support.data_text(body)}
            end
          end)
        end
      },
      %{
        "name" => "apps_update",
        "description" =>
          "Edit an app (branch, host, port, repo, runtime, auto_deploy, indexable, runtime_apt_packages). Alternative for apt deps: .cleat_deploy/runtime-packages",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "app" => Schema.app(),
            "branch" => %{"type" => "string"},
            "host" => %{"type" => "string"},
            "port" => %{"type" => "integer"},
            "repo" => %{"type" => "string"},
            "runtime" => %{"type" => "string"},
            "auto_deploy" => %{"type" => "boolean"},
            "indexable" => %{
              "type" => "boolean",
              "description" => "Allow search engines to index a static site"
            },
            "runtime_apt_packages" => @runtime_apt_packages,
            "panel" => Schema.panel(),
            "token" => Schema.token()
          },
          "required" => ["app"]
        },
        "handler" => fn args ->
          attrs =
            %{
              "branch" => args["branch"],
              "host" => args["host"],
              "port" => args["port"],
              "github_repo" => args["repo"],
              "runtime" => args["runtime"],
              "auto_deploy" => args["auto_deploy"],
              "indexable" => args["indexable"],
              "runtime_apt_packages" => args["runtime_apt_packages"]
            }
            |> Map.reject(fn {_k, v} -> is_nil(v) end)

          if attrs == %{} do
            {:error,
             "nothing to update: pass branch, host, port, repo, runtime, auto_deploy, indexable or runtime_apt_packages"}
          else
            Support.with_client(args, fn client ->
              with {:ok, body} <- Client.update_app(client, args["app"], attrs),
                   do: {:ok, Support.data_text(body)}
            end)
          end
        end
      },
      %{
        "name" => "apps_logs",
        "description" => "Runtime (systemd) logs for an app",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "app" => Schema.app(),
            "tail" => %{"type" => "integer"},
            "since" => %{"type" => "string"},
            "grep" => %{"type" => "string"},
            "panel" => Schema.panel(),
            "token" => Schema.token()
          },
          "required" => ["app"]
        },
        "handler" => fn args ->
          Support.with_client(args, fn client ->
            with {:ok, body} <-
                   Client.app_logs(client, args["app"], %{
                     tail: args["tail"],
                     since: args["since"],
                     grep: args["grep"]
                   }),
                 do: {:ok, Support.data_text(body)}
          end)
        end
      },
      %{
        "name" => "apps_query",
        "description" =>
          "Run one read-only SQL statement (SELECT, WITH, EXPLAIN, SHOW, PRAGMA) against the app's Postgres addon or local SQLite. Remote Turso/libSQL is unsupported.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "app" => Schema.app(),
            "sql" => %{"type" => "string", "description" => "One read-only SQL statement"},
            "limit" => %{
              "type" => "integer",
              "description" => "Max rows, 1-200 (default 50)"
            },
            "panel" => Schema.panel(),
            "token" => Schema.token()
          },
          "required" => ["app", "sql"]
        },
        "handler" => fn args ->
          attrs =
            case args["limit"] do
              limit when is_integer(limit) -> %{"sql" => args["sql"], "limit" => limit}
              _ -> %{"sql" => args["sql"]}
            end

          Support.with_client(args, fn client ->
            with {:ok, body} <- Client.query_app(client, args["app"], attrs),
                 do: {:ok, Support.data_text(body)}
          end)
        end
      }
    ]
  end
end
