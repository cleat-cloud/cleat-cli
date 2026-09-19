defmodule Cleat.Commands.Init do
  @moduledoc false

  alias Cleat.Output

  @manifest_dir ".cleat_deploy"
  @manifest_path Path.join(@manifest_dir, "deploy.json")

  def run(opts) do
    path = Path.join(File.cwd!(), @manifest_path)

    if File.exists?(path) and !opts[:yes] do
      {:error, "#{@manifest_path} already exists. Re-run with --yes to overwrite."}
    else
      manifest = build_manifest(opts)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, Jason.encode!(manifest, pretty: true) <> "\n")

      Output.success("Created #{@manifest_path}")
      Output.info("Commit it so the panel can read your deploy settings.")
      :ok
    end
  end

  defp build_manifest(opts) do
    runtime = opts[:runtime] || detect_runtime()

    %{"runtime" => runtime}
    |> maybe_put("release_name", opts[:release_name] || default_release_name(runtime))
    |> maybe_put("systemd_unit", opts[:systemd_unit])
    |> maybe_put("release_path", opts[:release_path])
    |> maybe_put("build_dir", opts[:build_dir])
    |> maybe_put("memory_max_mb", opts[:memory_max_mb] || 400)
    |> maybe_put("caddy_mode", opts[:caddy_mode])
    |> maybe_put("caddy_listen_port", opts[:caddy_listen_port])
    |> put_binaries(runtime, opts)
    |> maybe_put("solo_server", opts[:solo_server])
  end

  defp detect_runtime do
    cond do
      File.exists?("go.mod") and not File.exists?("mix.exs") -> "golang"
      true -> "phoenix"
    end
  end

  defp default_release_name("golang"), do: nil
  defp default_release_name("phoenix"), do: mix_app()

  defp mix_app do
    with true <- File.exists?("mix.exs"),
         contents <- File.read!("mix.exs"),
         [_, app] <- Regex.run(~r/\bapp:\s*:([a-zA-Z0-9_]+)/, contents) do
      app
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp put_binaries(manifest, "golang", opts) do
    manifest
    |> maybe_put("binaries", parse_binaries(opts[:binaries]) || go_binaries())
  end

  defp put_binaries(manifest, _runtime, _opts), do: manifest

  defp parse_binaries(nil), do: nil

  defp parse_binaries(value) when is_binary(value) do
    case String.split(value, ~r/[\s,]+/, trim: true) do
      [] -> nil
      list -> list
    end
  end

  defp go_binaries do
    case Path.wildcard("cmd/*/main.go") do
      [] -> nil
      paths -> Enum.map(paths, fn path -> path |> Path.dirname() |> Path.basename() end)
    end
  end

  defp maybe_put(manifest, _key, nil), do: manifest
  defp maybe_put(manifest, _key, ""), do: manifest
  defp maybe_put(manifest, key, value), do: Map.put(manifest, key, value)
end
