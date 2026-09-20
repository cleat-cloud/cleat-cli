defmodule Cleat.Commands.Drop do
  @moduledoc """
  Git-less deploy: package a local folder and publish it as a static site.
  """

  alias Cleat.{Client, Commands, Output}
  alias Cleat.Commands.Deploy

  @usage "usage: cleat drop [DIR|FILE] --app APP   (or --server ID --host DOMAIN [--slug SLUG])"
  @excludes ~w(.git node_modules .DS_Store)

  def run(args, opts) do
    target = List.first(args) || "."
    expanded = Path.expand(target)

    cond do
      File.regular?(expanded) -> drop_file(target, expanded, opts)
      File.dir?(expanded) -> drop_dir(target, expanded, opts)
      true -> {:error, "not a file or directory: #{target}"}
    end
  end

  # A single file is staged in a temp dir so it can be packed like a folder.
  # HTML becomes index.html so the site root serves it.
  defp drop_file(label, file, opts) do
    staging =
      Path.join(
        System.tmp_dir!(),
        "cleat_drop_site_#{System.system_time(:millisecond)}_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(staging)

    name =
      if String.downcase(Path.extname(file)) in [".html", ".htm"] do
        "index.html"
      else
        Path.basename(file)
      end

    slug = Path.basename(file) |> Path.rootname() |> slugify()

    try do
      with :ok <- File.cp(file, Path.join(staging, name)) do
        drop_dir(label, staging, opts, slug)
      else
        {:error, reason} -> {:error, "could not stage #{label}: #{:file.format_error(reason)}"}
      end
    after
      File.rm_rf(staging)
    end
  end

  defp drop_dir(label, dir, opts) do
    drop_dir(label, dir, opts, slugify(Path.basename(dir)))
  end

  defp drop_dir(label, dir, opts, default_slug) do
    with {:ok, tarball} <- pack(dir) do
      try do
        with {:ok, client} <- Commands.client(opts),
             {:ok, app} <- resolve_app(client, opts, default_slug),
             {:ok, body} <- Client.create_drop(client, app, tarball, opts[:ref]) do
          deployment = Commands.data(body)

          if opts[:json] do
            Output.json(deployment)
          else
            Output.success("Dropped #{label} → deploy ##{deployment["id"]} queued for #{app}")
          end

          if opts[:watch], do: Deploy.watch(client, deployment["id"]), else: :ok
        end
      after
        File.rm(tarball)
      end
    end
  end

  defp resolve_app(client, opts, default_slug) do
    case opts[:app] do
      app when is_binary(app) and app != "" -> {:ok, app}
      _ -> register_app(client, opts, default_slug)
    end
  end

  defp register_app(client, opts, default_slug) do
    slug = opts[:slug] || default_slug

    cond do
      is_nil(opts[:server]) ->
        {:error, @usage}

      is_nil(slug) ->
        {:error, "could not derive a slug; pass --slug"}

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
