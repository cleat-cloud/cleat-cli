defmodule Cleat.Commands.Apps do
  @moduledoc false

  alias Cleat.{Client, Commands, Output}

  @usage "usage: cleat apps list | cleat apps show APP | cleat apps create --name N --repo owner/repo --host H --server ID | cleat apps update APP [--branch B] [--auto-deploy|--no-auto-deploy]"

  def run([], opts), do: list(opts)
  def run(["list"], opts), do: list(opts)
  def run(["show", app], opts), do: show(app, opts)
  def run(["create"], opts), do: create(opts)
  def run(["update", app | _rest], opts), do: update(app, opts)
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
            ["Auto deploy", data["auto_deploy"]],
            ["Server", server_name(data)],
            ["Systemd unit", data["systemd_unit"]],
            ["Release path", data["release_path"]]
          ],
          ["Field", "Value"]
        )
      end

      :ok
    end
  end

  defp create(opts) do
    attrs = %{
      "name" => opts[:name],
      "slug" => opts[:slug] || slugify(opts[:name]),
      "github_repo" => opts[:repo],
      "branch" => opts[:branch] || "main",
      "host" => opts[:host],
      "port" => opts[:port] || 4000,
      "runtime" => opts[:runtime] || "phoenix",
      "server_id" => opts[:server]
    }

    case missing(attrs, [
           {"name", "--name"},
           {"github_repo", "--repo"},
           {"host", "--host"},
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

  defp update(app, opts) do
    attrs =
      %{}
      |> maybe_put_branch(opts)
      |> maybe_put_auto_deploy(opts)

    if attrs == %{} do
      {:error, "nothing to update: pass --branch and/or --auto-deploy"}
    else
      with {:ok, client} <- Commands.client(opts),
           {:ok, body} <- Client.update_app(client, app, attrs) do
        data = Commands.data(body)

        Output.success(
          "Updated #{data["slug"]} (branch=#{data["branch"]}, auto_deploy=#{data["auto_deploy"]})"
        )

        :ok
      end
    end
  end

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

  defp missing(attrs, required) do
    required
    |> Enum.filter(fn {key, _flag} -> attrs[key] in [nil, ""] end)
    |> Enum.map(fn {_key, flag} -> flag end)
  end

  defp server_name(%{"server" => %{"name" => name}}) when is_binary(name), do: name
  defp server_name(%{"server" => %{"id" => id}}) when is_integer(id), do: "##{id}"
  defp server_name(_), do: "—"

  defp slugify(nil), do: nil

  defp slugify(name) when is_binary(name) do
    slug =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    if slug == "", do: nil, else: slug
  end
end
