defmodule Cleat.MCP.Tools do
  @moduledoc """
  Static registry of MCP tools exposed by `cleat mcp`.

  Each tool declares a name, description, JSON Schema and a handler that reuses
  `Cleat.Client`/`Cleat.Commands`. Handlers return `{:ok, json_string}` or
  `{:error, message}`; the server turns errors into `isError` tool results.
  """

  alias Cleat.{Client, Commands}

  @panel %{"type" => "string", "description" => "Panel base URL override"}
  @token %{"type" => "string", "description" => "Bearer token override"}
  @app %{"type" => "string", "description" => "App id or slug"}

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
      |> Enum.reject(&present?(args, &1))

    case missing do
      [] -> :ok
      fields -> {:error, "missing required argument(s): #{Enum.join(fields, ", ")}"}
    end
  end

  defp present?(args, key) do
    case Map.get(args, key) do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  defp opts(args) do
    %{}
    |> maybe_put(:panel, args["panel"])
    |> maybe_put(:token, args["token"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp json(data), do: Jason.encode!(data)

  defp with_client(args, fun) do
    with :ok <- validate_token(args),
         {:ok, client} <- Commands.client(opts(args)) do
      fun.(client)
    end
  end

  defp validate_token(%{"token" => "-"}),
    do: {:error, "token '-' (stdin) is not supported over MCP"}

  defp validate_token(_args), do: :ok

  defp data_text(body), do: json(Commands.data(body))

  defp resolve_drop_app(_client, %{"app" => app}) when is_binary(app) and app != "" do
    {:ok, app}
  end

  defp resolve_drop_app(client, args) do
    if present?(args, "server") and present?(args, "host") do
      register_static_app(client, args)
    else
      {:error, "drop requires app, or server and host to register one"}
    end
  end

  defp register_static_app(client, args) do
    slug = args["slug"] || Cleat.Slug.from_name(Path.basename(args["path"]))

    attrs =
      %{
        "name" => slug,
        "slug" => slug,
        "host" => args["host"],
        "server_id" => args["server"],
        "runtime" => "static"
      }
      |> Map.reject(fn {_k, v} -> is_nil(v) or v == "" end)

    with {:ok, body} <- Client.create_app(client, attrs) do
      {:ok, Commands.data(body)["slug"]}
    end
  end

  defp tools do
    [
      %{
        "name" => "whoami",
        "description" => "Show the authenticated user and tenant",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{"panel" => @panel, "token" => @token}
        },
        "handler" => fn args ->
          with_client(args, fn client ->
            with {:ok, body} <- Client.me(client), do: {:ok, data_text(body)}
          end)
        end
      },
      %{
        "name" => "servers_list",
        "description" => "List registered servers",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{"panel" => @panel, "token" => @token}
        },
        "handler" => fn args ->
          with_client(args, fn client ->
            with {:ok, body} <- Client.list_servers(client), do: {:ok, data_text(body)}
          end)
        end
      },
      %{
        "name" => "apps_list",
        "description" => "List apps",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{"panel" => @panel, "token" => @token}
        },
        "handler" => fn args ->
          with_client(args, fn client ->
            with {:ok, body} <- Client.list_apps(client), do: {:ok, data_text(body)}
          end)
        end
      },
      %{
        "name" => "apps_show",
        "description" => "Show one app by id or slug",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{"app" => @app, "panel" => @panel, "token" => @token},
          "required" => ["app"]
        },
        "handler" => fn args ->
          with_client(args, fn client ->
            with {:ok, body} <- Client.get_app(client, args["app"]), do: {:ok, data_text(body)}
          end)
        end
      },
      %{
        "name" => "apps_create",
        "description" => "Create an app",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "name" => %{"type" => "string"},
            "repo" => %{"type" => "string", "description" => "owner/repo"},
            "host" => %{"type" => "string"},
            "server" => %{"type" => "string"},
            "runtime" => %{"type" => "string"},
            "slug" => %{"type" => "string"},
            "branch" => %{"type" => "string"},
            "port" => %{"type" => "integer"},
            "panel" => @panel,
            "token" => @token
          },
          "required" => ["name", "repo", "host", "server"]
        },
        "handler" => fn args ->
          attrs =
            %{
              "name" => args["name"],
              "github_repo" => args["repo"],
              "host" => args["host"],
              "server_id" => args["server"],
              "slug" => args["slug"],
              "branch" => args["branch"],
              "port" => args["port"],
              "runtime" => args["runtime"]
            }
            |> Map.reject(fn {_k, v} -> is_nil(v) or v == "" end)

          with_client(args, fn client ->
            with {:ok, body} <- Client.create_app(client, attrs), do: {:ok, data_text(body)}
          end)
        end
      },
      %{
        "name" => "apps_update",
        "description" => "Edit an app (branch, host, port, repo, runtime, auto_deploy)",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "app" => @app,
            "branch" => %{"type" => "string"},
            "host" => %{"type" => "string"},
            "port" => %{"type" => "integer"},
            "repo" => %{"type" => "string"},
            "runtime" => %{"type" => "string"},
            "auto_deploy" => %{"type" => "boolean"},
            "panel" => @panel,
            "token" => @token
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
              "auto_deploy" => args["auto_deploy"]
            }
            |> Map.reject(fn {_k, v} -> is_nil(v) end)

          if attrs == %{} do
            {:error, "nothing to update: pass branch, host, port, repo, runtime or auto_deploy"}
          else
            with_client(args, fn client ->
              with {:ok, body} <- Client.update_app(client, args["app"], attrs),
                   do: {:ok, data_text(body)}
            end)
          end
        end
      },
      %{
        "name" => "apps_logs",
        "description" => "Runtime (systemd) logs for an app",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{"app" => @app, "panel" => @panel, "token" => @token},
          "required" => ["app"]
        },
        "handler" => fn args ->
          with_client(args, fn client ->
            with {:ok, body} <- Client.app_logs(client, args["app"]), do: {:ok, data_text(body)}
          end)
        end
      },
      %{
        "name" => "env_list",
        "description" => "List env vars (secrets masked unless reveal is true)",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "app" => @app,
            "reveal" => %{"type" => "boolean"},
            "panel" => @panel,
            "token" => @token
          },
          "required" => ["app"]
        },
        "handler" => fn args ->
          with_client(args, fn client ->
            with {:ok, body} <- Client.list_env(client, args["app"], args["reveal"] == true),
                 do: {:ok, data_text(body)}
          end)
        end
      },
      %{
        "name" => "env_set",
        "description" => "Upsert env vars on an app",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "app" => @app,
            "vars" => %{"type" => "object", "additionalProperties" => %{"type" => "string"}},
            "panel" => @panel,
            "token" => @token
          },
          "required" => ["app", "vars"]
        },
        "handler" => fn args ->
          with_client(args, fn client ->
            with {:ok, body} <- Client.set_env(client, args["app"], %{vars: args["vars"]}),
                 do: {:ok, data_text(body)}
          end)
        end
      },
      %{
        "name" => "env_unset",
        "description" => "Delete an env var from an app",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "app" => @app,
            "key" => %{"type" => "string"},
            "panel" => @panel,
            "token" => @token
          },
          "required" => ["app", "key"]
        },
        "handler" => fn args ->
          with_client(args, fn client ->
            with {:ok, body} <- Client.delete_env(client, args["app"], args["key"]),
                 do: {:ok, data_text(body)}
          end)
        end
      },
      %{
        "name" => "deploy",
        "description" => "Queue a deploy and return the deployment id (does not wait)",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "app" => @app,
            "ref" => %{"type" => "string"},
            "panel" => @panel,
            "token" => @token
          },
          "required" => ["app"]
        },
        "handler" => fn args ->
          with_client(args, fn client ->
            with {:ok, body} <-
                   Client.create_deployment(client, args["app"], %{git_ref: args["ref"]}),
                 do: {:ok, data_text(body)}
          end)
        end
      },
      %{
        "name" => "deploy_status",
        "description" => "List recent deployments for an app",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{"app" => @app, "panel" => @panel, "token" => @token},
          "required" => ["app"]
        },
        "handler" => fn args ->
          with_client(args, fn client ->
            with {:ok, body} <- Client.list_deployments(client, args["app"]),
                 do: {:ok, data_text(body)}
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
            "panel" => @panel,
            "token" => @token
          },
          "required" => ["id"]
        },
        "handler" => fn args ->
          with_client(args, fn client ->
            with {:ok, body} <- Client.get_deployment(client, args["id"]),
                 do: {:ok, data_text(body)}
          end)
        end
      },
      %{
        "name" => "cancel_deploy",
        "description" => "Cancel the active deploy of an app",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{"app" => @app, "panel" => @panel, "token" => @token},
          "required" => ["app"]
        },
        "handler" => fn args ->
          with_client(args, fn client ->
            with {:ok, body} <- Client.cancel_deploy(client, args["app"]),
                 do: {:ok, data_text(body)}
          end)
        end
      },
      %{
        "name" => "drop",
        "description" => "Publish a local folder or file as a static site",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "path" => %{"type" => "string"},
            "app" => @app,
            "server" => %{
              "type" => "string",
              "description" => "Server id to register a static app on"
            },
            "host" => %{"type" => "string", "description" => "Host for the registered static app"},
            "slug" => %{"type" => "string", "description" => "Slug for the registered static app"},
            "ref" => %{"type" => "string"},
            "panel" => @panel,
            "token" => @token
          },
          "required" => ["path"]
        },
        "handler" => fn args ->
          with {:ok, tarball} <- Cleat.Pack.pack(args["path"]) do
            try do
              with_client(args, fn client ->
                with {:ok, app} <- resolve_drop_app(client, args),
                     {:ok, body} <- Client.create_drop(client, app, tarball, args["ref"]),
                     do: {:ok, data_text(body)}
              end)
            after
              File.rm(tarball)
            end
          end
        end
      },
      %{
        "name" => "init_project",
        "description" => "Write .cleat_deploy/deploy.json in the current directory",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "runtime" => %{"type" => "string"},
            "build_command" => %{"type" => "string"},
            "start_command" => %{"type" => "string"},
            "node_version" => %{"type" => "string"},
            "memory_max_mb" => %{"type" => "integer"},
            "overwrite" => %{"type" => "boolean"}
          }
        },
        "handler" => fn args ->
          opts = %{yes: args["overwrite"] == true}
          opts = if args["runtime"], do: Map.put(opts, :runtime, args["runtime"]), else: opts

          opts =
            if args["build_command"],
              do: Map.put(opts, :build_command, args["build_command"]),
              else: opts

          opts =
            if args["start_command"],
              do: Map.put(opts, :start_command, args["start_command"]),
              else: opts

          opts =
            if args["node_version"],
              do: Map.put(opts, :node_version, args["node_version"]),
              else: opts

          opts =
            if args["memory_max_mb"],
              do: Map.put(opts, :memory_max_mb, args["memory_max_mb"]),
              else: opts

          case Cleat.Commands.Init.write(opts) do
            {:ok, %{path: path, runtime: runtime}} ->
              {:ok, json(%{"created" => path, "runtime" => runtime})}

            {:error, message} ->
              {:error, message}
          end
        end
      }
    ]
  end
end
