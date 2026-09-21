defmodule Cleat.Commands.Drop do
  @moduledoc """
  Git-less deploy: package a local folder and publish it as a static site.
  """

  alias Cleat.{Client, Commands, Output, Static}
  alias Cleat.Commands.Deploy

  @usage "usage: cleat drop [DIR|FILE] --app APP   (or --server ID --host DOMAIN [--slug SLUG])"

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

    slug = Path.basename(file) |> Path.rootname() |> Cleat.Slug.from_name()

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
    drop_dir(label, dir, opts, Cleat.Slug.from_name(Path.basename(dir)))
  end

  defp drop_dir(label, dir, opts, default_slug) do
    with {:ok, tarball} <- Cleat.Pack.pack(dir) do
      try do
        with {:ok, client} <- Commands.client(opts),
             {:ok, app} <- resolve_app(client, opts, default_slug, dir),
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

  defp resolve_app(client, opts, default_slug, dir) do
    case opts[:app] do
      app when is_binary(app) and app != "" ->
        {:ok, app}

      _ ->
        slug = opts[:slug] || default_slug

        case register_or_reuse_app(client, opts, slug, dir) do
          {:error, :exists} -> {:ok, slug}
          other -> other
        end
    end
  end

  defp register_or_reuse_app(client, opts, slug, dir) do
    cond do
      is_nil(opts[:server]) ->
        {:error, @usage}

      is_nil(slug) ->
        {:error, "could not derive a slug; pass --slug"}

      true ->
        with :ok <- check_existing(client, slug, opts),
             {:ok, host} <- drop_host(slug, opts, dir),
             {:ok, app_slug} <- create_app(client, slug, host, opts) do
          {:ok, app_slug}
        end
    end
  end

  # Static targets default to <slug>.<sites_base_domain> when no host is given.
  defp drop_host(slug, opts, dir) do
    case Commands.host(opts) do
      {:ok, host} ->
        {:ok, host}

      {:error, :missing_host} ->
        if Static.detect?(dir), do: Commands.static_host(slug, opts), else: {:error, @usage}

      {:error, message} ->
        {:error, message}
    end
  end

  defp check_existing(client, slug, opts) do
    case Client.list_apps(client) do
      {:ok, body} ->
        case Enum.find(Commands.data(body), &(&1["slug"] == slug)) do
          nil ->
            :ok

          %{"runtime" => "static"} = app ->
            reuse_static(app, slug, opts)

          %{"runtime" => runtime} ->
            {:error,
             "app #{slug} already exists with runtime #{runtime}; use a different --slug " <>
               "(or pass --app to target another app)"}

          _other ->
            :ok
        end

      {:error, message} ->
        {:error, message}
    end
  end

  # An existing static app can be reused when the user did not pin a host, or
  # pinned the same host it already has. A conflicting explicit host is an error
  # so the request is never silently discarded.
  defp reuse_static(app, slug, opts) do
    case Commands.host(opts) do
      {:ok, requested} ->
        if normalize_host(requested) == normalize_host(app["host"]) do
          {:error, :exists}
        else
          {:error,
           "app #{slug} already exists as static on #{app["host"]}; drop without " <>
             "--host/--subdomain to reuse it, or use a different --slug"}
        end

      {:error, :missing_host} ->
        {:error, :exists}

      {:error, message} ->
        {:error, message}
    end
  end

  defp normalize_host(nil), do: nil

  defp normalize_host(host) when is_binary(host) do
    host |> String.downcase() |> String.trim_trailing(".")
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
end
