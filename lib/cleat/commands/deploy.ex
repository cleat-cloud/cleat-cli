defmodule Cleat.Commands.Deploy do
  @moduledoc false

  alias Cleat.{Client, Commands, Output, Poller, Runtime, Static}

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
          slug = repo_slug(repo, opts)

          if Enum.any?(apps, &(&1["slug"] == slug)) do
            {:error, "app #{slug} already exists; pass --slug to pick another name"}
          else
            register_repo(client, repo, opts)
          end
      end
    end
  end

  defp register_repo(client, repo, opts) do
    cond do
      is_nil(opts[:server]) ->
        {:error, "#{repo} is not registered. Pass --server ID (and a host)."}

      true ->
        slug = repo_slug(repo, opts)

        case repo_host(slug, repo, opts) do
          {:ok, host} -> register(client, repo, host, slug, opts)
          {:error, message} -> {:error, message}
        end
    end
  end

  # Static-only repos default to <slug>.<sites_base_domain> when the local
  # checkout is a plain static site and no host was given.
  defp repo_host(slug, repo, opts) do
    case Commands.host(opts) do
      {:ok, host} ->
        {:ok, host}

      {:error, :missing_host} ->
        if Static.detect?(File.cwd!()) do
          Commands.static_host(slug, opts)
        else
          {:error, "#{repo} is not registered. Pass --host DOMAIN or --subdomain NAME."}
        end

      {:error, message} ->
        {:error, message}
    end
  end

  defp register(client, repo, host, slug, opts) do
    attrs = %{
      "name" => opts[:name] || slug,
      "slug" => slug,
      "github_repo" => repo,
      "branch" => opts[:branch] || "main",
      "host" => host,
      "server_id" => opts[:server],
      "runtime" => runtime(opts)
    }

    with {:ok, body} <- Client.create_app(client, attrs) do
      app = Commands.data(body)
      Output.success("Registered app #{app["slug"]} (##{app["id"]})")
      {:ok, app["slug"]}
    end
  end

  # An explicit --slug wins; otherwise slugify the repo basename, dropping a
  # trailing `.git` so `owner/repo.git` registers as `repo`.
  defp repo_slug(repo, opts) do
    opts[:slug] || Cleat.Slug.from_name(repo_basename(repo))
  end

  defp repo_basename(repo) do
    base = Path.basename(repo)

    if String.ends_with?(base, ".git"), do: Path.rootname(base), else: base
  end

  # An explicit --runtime always wins; otherwise detect from the local checkout so
  # a TanStack Start / Next repo is registered as `node`, not `phoenix`.
  defp runtime(opts) do
    case opts[:runtime] do
      nil -> Runtime.detect()
      value -> Runtime.normalize(value) || value
    end
  end

  @doc false
  def watch(client, id, opts \\ []) do
    fetch = fn -> Client.get_deployment(client, id) end

    step = fn body, state ->
      deployment = Commands.data(body)
      status = deployment["status"]
      log = deployment["log"] || ""

      if status != state.status, do: Output.info("→ #{status}")
      :ok = print_log_delta(log, state.log)

      cond do
        status == "success" ->
          Output.success("Deploy ##{id} succeeded")
          :done

        status == "failed" ->
          {:error, "deploy ##{id} failed"}

        true ->
          {:continue, %{state | status: status, log: log}}
      end
    end

    Poller.poll(fetch, step, %{status: nil, log: ""}, opts)
  end

  defp print_log_delta(log, printed) do
    case Output.log_delta(printed, log) do
      "" -> :ok
      delta -> IO.write(delta)
    end
  end
end
