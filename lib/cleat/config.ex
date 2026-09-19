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
      _ -> Path.join(config_dir(), "config.json")
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
    File.mkdir_p!(Path.dirname(path()))
    File.write!(path(), Jason.encode!(config, pretty: true) <> "\n")
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

  defp config_dir do
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
