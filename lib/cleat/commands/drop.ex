defmodule Cleat.Commands.Drop do
  @moduledoc """
  Git-less deploy: package a local folder and publish it as a static site.
  """

  alias Cleat.{Client, Commands, Output}
  alias Cleat.Commands.Deploy

  @usage "usage: cleat drop [DIR] --app APP   (or --server ID --host DOMAIN [--slug SLUG])"
  @excludes ~w(.git node_modules .DS_Store)

  def run(args, opts) do
    dir = List.first(args) || "."
    expanded = Path.expand(dir)

    cond do
      not File.dir?(expanded) ->
        {:error, "not a directory: #{dir}"}

      true ->
        with {:ok, tarball} <- pack(expanded) do
          try do
            with {:ok, client} <- Commands.client(opts),
                 {:ok, app} <- resolve_app(client, expanded, opts),
                 {:ok, body} <- Client.create_drop(client, app, tarball, opts[:ref]) do
              deployment = Commands.data(body)

              if opts[:json] do
                Output.json(deployment)
              else
                Output.success("Dropped #{dir} → deploy ##{deployment["id"]} queued for #{app}")
              end

              if opts[:watch], do: Deploy.watch(client, deployment["id"]), else: :ok
            end
          after
            File.rm(tarball)
          end
        end
    end
  end

  defp resolve_app(client, dir, opts) do
    case opts[:app] do
      app when is_binary(app) and app != "" -> {:ok, app}
      _ -> register_app(client, dir, opts)
    end
  end

  defp register_app(client, dir, opts) do
    slug = opts[:slug] || slugify(Path.basename(dir))

    cond do
      is_nil(opts[:server]) ->
        {:error, @usage}

      is_nil(slug) ->
        {:error, "could not derive a slug from #{dir}; pass --slug"}

      true ->
        case Commands.host(opts) do
          {:ok, host} -> create_app(client, slug, host, opts)
          {:error, :missing_host} -> {:error, @usage}
          {:error, message} -> {:error, message}
        end
    end
  end

  defp create_app(client, slug, host, opts) do
    attrs = %{
      "name" => opts[:name] || slug,
      "slug" => slug,
      "host" => host,
      "server_id" => opts[:server],
      "runtime" => "static"
    }

    with {:ok, body} <- Client.create_app(client, attrs) do
      app = Commands.data(body)
      Output.success("Registered static app #{app["slug"]} (##{app["id"]}) → #{host}")
      {:ok, app["slug"]}
    end
  end

  defp pack(dir) do
    path =
      Path.join(
        System.tmp_dir!(),
        "cleat_drop_#{System.system_time(:millisecond)}_#{:erlang.unique_integer([:positive])}.tar.gz"
      )

    args =
      ["-czf", path] ++
        Enum.flat_map(@excludes, &["--exclude", &1]) ++
        ["-C", dir, "."]

    case System.cmd("tar", args, stderr_to_stdout: true) do
      {_output, 0} -> {:ok, path}
      {output, _code} -> {:error, "tar failed: #{String.trim(output)}"}
    end
  end

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
