defmodule Cleat.Config do
  @moduledoc """
  Reads and writes the CLI's global configuration.

  The configuration lives at `~/.config/cleat/config.json` (or
  `$CLEAT_CONFIG` when set) and holds the panel URL plus the bearer token
  issued by `cleat login`.
  """

  @app "cleat"
  @env_config "CLEAT_CONFIG"

  @doc "Path to the global config file."
  def path do
    case System.get_env(@env_config) do
      path when is_binary(path) and path != "" -> path
      _ -> Path.join(default_dir(), "config.json")
    end
  end

  @doc "Loads the config map, returning `%{}` when it does not exist yet."
  def load do
    case File.read(path()) do
      {:ok, contents} -> decode(contents)
      {:error, _} -> %{}
    end
  end

  @doc "Persists the config map to disk."
  def save(config) when is_map(config) do
    file = path()
    dir = Path.dirname(file)
    created? = not File.dir?(dir)

    File.mkdir_p!(dir)

    # Only tighten the directory when we created it or it is ours; never chmod
    # a shared directory the user pointed CLEAT_CONFIG at.
    if created? or dir == default_dir() do
      _ = File.chmod(dir, 0o700)
    end

    File.write!(file, Jason.encode!(config, pretty: true) <> "\n")
    _ = File.chmod(file, 0o600)
    :ok
  end

  @doc "Writes a single key to the config, preserving the rest."
  def put(key, value) when is_binary(key) do
    load()
    |> Map.put(key, value)
    |> save()
  end

  @doc "Removes a key from the config."
  def delete(key) when is_binary(key) do
    load()
    |> Map.delete(key)
    |> save()
  end

  @doc "Configured panel URL, if any."
  def panel_url, do: get("panel_url")

  @doc "Configured bearer token, if any."
  def token, do: get("token")

  def get(key) when is_binary(key) do
    case Map.get(load(), key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp default_dir do
    base =
      non_empty_env("XDG_CONFIG_HOME") ||
        Path.join(System.user_home!(), ".config")

    Path.join(base, @app)
  end

  defp non_empty_env(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp decode(contents) do
    case Jason.decode(contents) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end
end
