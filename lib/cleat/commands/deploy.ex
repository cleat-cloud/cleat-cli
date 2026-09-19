defmodule Cleat.Commands.Deploy do
  @moduledoc false

  alias Cleat.{Client, Commands, Output, Poller}

  def run(app, opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, app} <- resolve_app(client, app, opts),
         {:ok, body} <- Client.create_deployment(client, app, %{git_ref: opts[:ref]}) do
      deployment = Commands.data(body)

      if opts[:json] do
        Output.json(deployment)
      else
        Output.success("Deploy ##{deployment["id"]} queued for #{app} (#{deployment["status"]})")
      end

      if opts[:watch], do: watch(client, deployment["id"]), else: :ok
    end
  end

  @doc false
  def resolve_app(_client, app, _opts) when is_binary(app) and app != "", do: {:ok, app}

  def resolve_app(client, _app, opts) do
    case opts[:repo] do
      nil ->
        {:error, "usage: cleat deploy APP [--ref BRANCH] [--watch]  (or --repo owner/repo)"}

      repo ->
        resolve_repo(client, repo, opts)
    end
  end

  defp resolve_repo(client, repo, opts) do
    with {:ok, body} <- Client.list_apps(client) do
      apps = Commands.data(body)

      case Enum.find(apps, &(&1["github_repo"] == repo)) do
        %{"slug" => slug} ->
          {:ok, slug}

        nil ->
          register_repo(client, repo, opts)
      end
    end
  end

  defp register_repo(client, repo, opts) do
    cond do
      is_nil(opts[:server]) ->
        {:error, "#{repo} is not registered. Pass --server ID (and a host)."}

      true ->
        case Commands.host(opts) do
          {:ok, host} ->
            register(client, repo, host, opts)

          {:error, :missing_host} ->
            {:error, "#{repo} is not registered. Pass --host DOMAIN or --subdomain NAME."}

          {:error, message} ->
            {:error, message}
        end
    end
  end

  defp register(client, repo, host, opts) do
    slug = opts[:slug] || slugify(Path.basename(repo))

    attrs = %{
      "name" => opts[:name] || slug,
      "slug" => slug,
      "github_repo" => repo,
      "branch" => opts[:branch] || "main",
      "host" => host,
      "server_id" => opts[:server],
      "runtime" => opts[:runtime] || "phoenix"
    }

    with {:ok, body} <- Client.create_app(client, attrs) do
      app = Commands.data(body)
      Output.success("Registered app #{app["slug"]} (##{app["id"]})")
      {:ok, app["slug"]}
    end
  end

  @doc false
  def watch(client, id) do
    fetch = fn -> Client.get_deployment(client, id) end

    step = fn body, last_status ->
      deployment = Commands.data(body)
      status = deployment["status"]

      if status != last_status, do: Output.info("→ #{status}")

      cond do
        status == "success" ->
          Output.success("Deploy ##{id} succeeded")
          print_log(deployment)
          :done

        status == "failed" ->
          print_log(deployment)
          {:error, "deploy ##{id} failed"}

        true ->
          {:continue, status}
      end
    end

    Poller.poll(fetch, step, nil)
  end

  defp print_log(%{"log" => log}) when is_binary(log) and log != "" do
    Output.info("")
    Output.info(log)
  end

  defp print_log(_), do: :ok

  defp slugify(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
