defmodule Cleat.Commands.Config do
  @moduledoc false

  alias Cleat.{Config, Output}

  @usage "usage: cleat config | cleat config get KEY | cleat config set KEY VALUE | cleat config unset KEY"
  @writable ~w(base_domain panel_url)

  def run([], _opts), do: list()
  def run(["list"], _opts), do: list()
  def run(["get", key], _opts), do: get(key)
  def run(["set", key, value], _opts), do: set(key, value)
  def run(["unset", key], _opts), do: unset(key)
  def run(_args, _opts), do: {:error, @usage}

  defp list do
    config = Config.load()

    Output.table(
      [
        ["panel_url", config["panel_url"] || "—"],
        ["base_domain", config["base_domain"] || "—"],
        ["token", mask(config["token"])]
      ],
      ["KEY", "VALUE"]
    )

    Output.info("")
    Output.info("Config file: #{Config.path()}")
    :ok
  end

  defp get(key) do
    Output.info(Config.get(key) || "")
    :ok
  end

  defp set(key, value) do
    if key in @writable do
      Config.put(key, normalize(key, value))
      Output.success("Set #{key} = #{normalize(key, value)}")
      :ok
    else
      {:error, "unknown key #{inspect(key)} (writable: #{Enum.join(@writable, ", ")})"}
    end
  end

  defp unset(key) do
    Config.delete(key)
    Output.success("Unset #{key}")
    :ok
  end

  defp normalize("base_domain", value) do
    value |> String.trim() |> String.downcase() |> String.trim_trailing(".")
  end

  defp normalize(_key, value), do: String.trim(value)

  defp mask(nil), do: "—"

  defp mask(token) when is_binary(token) do
    if String.length(token) <= 12, do: "•••", else: String.slice(token, 0, 8) <> "…"
  end
end
