defmodule Mix.Tasks.Cleat.Install do
  @shortdoc "Builds the escript and installs it on your PATH"

  @moduledoc """
  Builds the `cleat` escript and copies it to an install directory.

      mix cleat.install
      mix cleat.install /usr/local/bin

  The destination defaults to `$CLEAT_INSTALL_DIR` when set, otherwise
  `~/.local/bin`. Wired up as `mix install`.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {_opts, argv, _invalid} = OptionParser.parse(args, strict: [])

    dest =
      List.first(argv) || System.get_env("CLEAT_INSTALL_DIR") ||
        Path.join(System.user_home!(), ".local/bin")

    Mix.Task.run("escript.build", [])

    source = Path.join(File.cwd!(), "cleat")

    unless File.exists?(source) do
      Mix.raise("Expected escript at #{source}, but it was not built")
    end

    File.mkdir_p!(dest)
    target = Path.join(dest, "cleat")
    File.cp!(source, target)
    File.chmod!(target, 0o755)

    Mix.shell().info([:green, "Installed cleat to #{target}"])

    unless path_includes?(dest) do
      Mix.shell().error(
        "Warning: #{dest} is not on your PATH — add it or re-run with a directory that is"
      )
    end
  end

  defp path_includes?(dir) do
    System.get_env("PATH", "")
    |> String.split(":", trim: true)
    |> Enum.any?(&(Path.expand(&1) == Path.expand(dir)))
  end
end
