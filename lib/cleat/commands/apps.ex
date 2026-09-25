defmodule Cleat.Commands.Apps do
  @moduledoc false

  alias Cleat.{Client, Commands, Output, Runtime}

  @usage "usage: cleat apps list | cleat apps show APP | cleat apps create --name N --repo owner/repo --host H --server ID [--apt pkg,pkg] | cleat apps update APP [--branch B] [--auto-deploy|--no-auto-deploy] [--indexable|--no-indexable] [--host H] [--port N] [--repo owner/repo] [--runtime R] [--apt pkg,pkg] | cleat apps delete APP --yes | cleat apps logs APP [--tail N] [--since S] [--grep T] [--follow]"

  def run([], opts), do: list(opts)
  def run(["list"], opts), do: list(opts)
  def run(["show", app], opts), do: show(app, opts)
  def run(["create"], opts), do: create(opts)
  def run(["update", app | _rest], opts), do: update(app, opts)
  def run(["delete", app | _rest], opts), do: delete(app, opts)
  def run(["logs", app | _rest], opts), do: logs(app, opts)
  def run(_args, _opts), do: {:error, @usage}

  defp list(opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.list_apps(client) do
      apps = Commands.data(body)

      if opts[:json] do
        Output.json(apps)
      else
        rows =
          Enum.map(apps, fn app ->
            [
              app["id"],
              app["slug"],
              app["github_repo"],
              app["branch"],
              app["runtime"],
              app["host"],
              server_name(app)
            ]
          end)

        Output.table(rows, ["ID", "SLUG", "REPO", "BRANCH", "RUNTIME", "HOST", "SERVER"])
      end

      :ok
    end
  end

  defp show(app, opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.get_app(client, app) do
      data = Commands.data(body)

      if opts[:json] do
        Output.json(data)
      else
        Output.table(
          [
            ["ID", data["id"]],
            ["Name", data["name"]],
            ["Slug", data["slug"]],
            ["Repo", data["github_repo"]],
            ["Branch", data["branch"]],
            ["Host", data["host"]],
            ["Port", data["port"]],
            ["Runtime", data["runtime"]],
            ["Apt packages", format_apt(data["runtime_apt_packages"])],
            ["Auto deploy", data["auto_deploy"]],
            ["Indexable", data["indexable"]],
            ["Server", server_name(data)],
            ["Systemd unit", data["systemd_unit"]],
            ["Release path", data["release_path"]],
            ["Data dir", data["data_dir"]]
          ],
          ["Field", "Value"]
        )
      end

      :ok
    end
  end

  defp create(opts) do
    case Commands.host(opts) do
      {:error, message} when is_binary(message) ->
        {:error, message}

      host_result ->
        host =
          case host_result do
            {:ok, value} -> value
            {:error, :missing_host} -> nil
          end

        attrs =
          %{
            "name" => opts[:name],
            "slug" => opts[:slug] || Cleat.Slug.from_name(opts[:name]),
            "github_repo" => opts[:repo],
            "branch" => opts[:branch] || "main",
            "host" => host,
            "port" => opts[:port] || 4000,
            "runtime" => runtime(opts),
            "server_id" => opts[:server]
          }
          |> maybe_put_apt(opts)

        case missing(attrs, [
               {"name", "--name"},
               {"github_repo", "--repo"},
               {"host", "--host (or --subdomain)"},
               {"server_id", "--server"}
             ]) do
          [] ->
            with {:ok, client} <- Commands.client(opts),
                 {:ok, body} <- Client.create_app(client, attrs) do
              app = Commands.data(body)
              Output.success("Created app #{app["slug"]} (##{app["id"]}) on #{server_name(app)}")
              :ok
            end

          missing ->
            {:error, "missing required options: #{Enum.join(missing, ", ")}"}
        end
    end
  end

  defp update(app, opts) do
    attrs =
      %{}
      |> maybe_put_branch(opts)
      |> maybe_put_auto_deploy(opts)
      |> maybe_put_indexable(opts)
      |> maybe_put_port(opts)
      |> maybe_put_repo(opts)
      |> maybe_put_runtime(opts)
      |> maybe_put_apt(opts)
      |> with_host(opts)

    case attrs do
      {:error, message} ->
        {:error, message}

      attrs when map_size(attrs) == 0 ->
        {:error,
         "nothing to update: pass --branch, --auto-deploy, --indexable, --host, --port, --repo, --runtime or --apt"}

      attrs ->
        with {:ok, client} <- Commands.client(opts),
             {:ok, body} <- Client.update_app(client, app, attrs) do
          data = Commands.data(body)

          Output.success(
            "Updated #{data["slug"]} (repo=#{data["github_repo"]}, branch=#{data["branch"]}, auto_deploy=#{data["auto_deploy"]}, indexable=#{data["indexable"]}, host=#{data["host"]}, port=#{data["port"]}, runtime=#{data["runtime"]})"
          )

          :ok
        end
    end
  end

  # An explicit --runtime always wins; otherwise detect from the local checkout so
  # a TanStack Start / Next repo is registered as `node`, not `phoenix`.
  defp runtime(opts) do
    case opts[:runtime] do
      nil -> Runtime.detect()
      value -> Runtime.normalize(value) || value
    end
  end

  defp with_host(attrs, opts) do
    case Commands.host(opts) do
      {:ok, host} -> Map.put(attrs, "host", host)
      {:error, :missing_host} -> attrs
      {:error, message} -> {:error, message}
    end
  end

  defp delete(app, opts) do
    if opts[:yes] do
      with {:ok, client} <- Commands.client(opts),
           {:ok, _body} <- Client.delete_app(client, app) do
        Output.success("Deleted app #{app}")
        :ok
      end
    else
      {:error, "refusing to delete #{app}: pass --yes to confirm"}
    end
  end

  defp logs(app, opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.app_logs(client, app, log_opts(opts)) do
      data = Commands.data(body)
      lines = data["lines"] || []

      if opts[:json] do
        Output.json(data)
        :ok
      else
        print_lines(lines, app, opts[:follow])

        if opts[:follow] do
          follow(client, app, log_opts(opts), MapSet.new(lines), 0)
        else
          :ok
        end
      end
    end
  end

  defp log_opts(opts), do: %{tail: opts[:tail], since: opts[:since], grep: opts[:grep]}

  defp print_lines([], app, true),
    do: Output.info("No runtime logs for #{app} yet. Following…")

  defp print_lines([], app, _follow), do: Output.info("No runtime logs for #{app}.")
  defp print_lines(lines, _app, _follow), do: Output.info(Enum.join(lines, "\n"))

  defp follow(client, app, log_opts, seen, polls) do
    if polls >= max_polls() do
      :ok
    else
      Process.sleep(interval_ms())

      case Client.app_logs(client, app, log_opts) do
        {:ok, body} ->
          lines = Commands.data(body)["lines"] || []
          {fresh, seen} = fresh_lines(lines, seen)
          Enum.each(fresh, &IO.puts/1)
          follow(client, app, log_opts, prune(seen, lines), polls + 1)

        {:error, message} ->
          Output.error(message)
          :ok
      end
    end
  end

  defp fresh_lines(lines, seen) do
    fresh = Enum.reject(lines, &MapSet.member?(seen, &1))
    {fresh, Enum.reduce(lines, seen, &MapSet.put(&2, &1))}
  end

  defp prune(seen, lines) do
    if MapSet.size(seen) > 5_000, do: MapSet.new(lines), else: seen
  end

  defp max_polls, do: Application.get_env(:cleat_cli, :logs_follow_max_polls, :infinity)
  defp interval_ms, do: Application.get_env(:cleat_cli, :logs_follow_interval_ms, 2_000)

  defp maybe_put_branch(attrs, opts) do
    case opts[:branch] do
      nil -> attrs
      branch -> Map.put(attrs, "branch", branch)
    end
  end

  defp maybe_put_auto_deploy(attrs, opts) do
    opts = Map.new(opts)

    if Map.has_key?(opts, :auto_deploy) do
      Map.put(attrs, "auto_deploy", opts[:auto_deploy])
    else
      attrs
    end
  end

  defp maybe_put_indexable(attrs, opts) do
    opts = Map.new(opts)

    if Map.has_key?(opts, :indexable) do
      Map.put(attrs, "indexable", opts[:indexable])
    else
      attrs
    end
  end

  defp maybe_put_port(attrs, opts) do
    case opts[:port] do
      nil -> attrs
      port -> Map.put(attrs, "port", port)
    end
  end

  defp maybe_put_repo(attrs, opts) do
    case opts[:repo] do
      nil -> attrs
      repo -> Map.put(attrs, "github_repo", repo)
    end
  end

  defp maybe_put_runtime(attrs, opts) do
    case opts[:runtime] do
      nil -> attrs
      value -> Map.put(attrs, "runtime", Runtime.normalize(value) || value)
    end
  end

  defp maybe_put_apt(attrs, opts) do
    case apt_packages(opts[:apt]) do
      nil -> attrs
      packages -> Map.put(attrs, "runtime_apt_packages", packages)
    end
  end

  defp apt_packages(nil), do: nil

  defp apt_packages(packages) when is_list(packages), do: packages

  defp apt_packages(packages) when is_binary(packages) do
    packages
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp format_apt(packages) when is_list(packages) and packages != [],
    do: Enum.join(packages, ", ")

  defp format_apt(_), do: "—"

  defp missing(attrs, required) do
    required
    |> Enum.filter(fn {key, _flag} -> attrs[key] in [nil, ""] end)
    |> Enum.map(fn {_key, flag} -> flag end)
  end

  defp server_name(%{"server" => %{"name" => name}}) when is_binary(name), do: name
  defp server_name(%{"server" => %{"id" => id}}) when is_integer(id), do: "##{id}"
  defp server_name(_), do: "—"
end
