defmodule Cleat.Runtime do
  @moduledoc """
  Detects a project's Cleat runtime from the files in the current directory.

  Shared by `cleat init` (manifest generation) and app registration, so a
  `cleat deploy --repo …` for a Next.js / TanStack Start repo is registered as
  `node` instead of silently defaulting to `phoenix`.
  """

  @runtimes ~w(phoenix golang static node rails)

  @doc """
  Detects the runtime for the current working directory, defaulting to `phoenix`.
  """
  def detect, do: do_detect(File.cwd!())

  @doc false
  def detect(dir) when is_binary(dir), do: do_detect(dir)

  defp do_detect(dir) do
    cond do
      file?(dir, "go.mod") and not file?(dir, "mix.exs") ->
        "golang"

      file?(dir, "mix.exs") ->
        "phoenix"

      rails?(dir) ->
        "rails"

      node_project?(dir) ->
        "node"

      file?(dir, "index.html") or file?(dir, "package.json") ->
        "static"

      true ->
        "phoenix"
    end
  end

  @doc "Normalizes a user-supplied runtime, returning nil when unrecognized."
  def normalize(runtime) when is_binary(runtime) do
    runtime = runtime |> String.trim() |> String.downcase()
    if runtime in @runtimes, do: runtime, else: nil
  end

  def normalize(_), do: nil

  defp rails?(dir) do
    file?(dir, "Gemfile") and
      (file?(dir, "config/application.rb") or gemfile_has_rails?(dir))
  end

  defp gemfile_has_rails?(dir) do
    case File.read(Path.join(dir, "Gemfile")) do
      {:ok, contents} -> String.contains?(contents, "rails")
      _ -> false
    end
  end

  # Next.js and TanStack Start run a long-lived Node server (SSR). Everything
  # else with a package.json is treated as a static build.
  defp node_project?(dir) do
    with {:ok, contents} <- File.read(Path.join(dir, "package.json")),
         {:ok, pkg} <- Jason.decode(contents) do
      deps = Map.merge(pkg["dependencies"] || %{}, pkg["devDependencies"] || %{})
      Enum.any?(Map.keys(deps), &node_framework?/1)
    else
      _ -> false
    end
  end

  defp node_framework?("next"), do: true

  defp node_framework?("@" <> rest),
    do: String.ends_with?(rest, "-start") or String.ends_with?(rest, "/start")

  defp node_framework?(_dep), do: false

  defp file?(dir, relative), do: File.exists?(Path.join(dir, relative))
end
