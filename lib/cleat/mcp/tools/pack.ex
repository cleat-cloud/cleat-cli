defmodule Cleat.MCP.Tools.Pack do
  @moduledoc """
  Packs a local folder or file into a tarball for the `drop` tool.

  Mirrors `Cleat.Commands.Drop.pack/1` (private) but returns a path the caller
  owns and never writes to stdout.
  """

  @excludes ~w(.git node_modules .DS_Store)

  @doc "Packs `path` into a temporary `.tar.gz` and returns its path."
  def pack(path) when is_binary(path) do
    expanded = Path.expand(path)

    cond do
      File.regular?(expanded) -> pack_file(expanded)
      File.dir?(expanded) -> pack_dir(expanded)
      true -> {:error, "not a file or directory: #{path}"}
    end
  end

  defp pack_dir(dir) do
    tarball = temp_path()

    args =
      ["-czf", tarball] ++
        Enum.flat_map(@excludes, &["--exclude", &1]) ++
        ["-C", dir, "."]

    case System.cmd("tar", args, stderr_to_stdout: true) do
      {_out, 0} -> {:ok, tarball}
      {out, _} -> {:error, "tar failed: #{String.trim(out)}"}
    end
  end

  defp pack_file(file) do
    staging =
      Path.join(
        System.tmp_dir!(),
        "cleat_pack_#{System.system_time(:millisecond)}_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(staging)

    name =
      if String.downcase(Path.extname(file)) in [".html", ".htm"] do
        "index.html"
      else
        Path.basename(file)
      end

    try do
      with :ok <- File.cp(file, Path.join(staging, name)) do
        pack_dir(staging)
      else
        {:error, reason} -> {:error, "could not stage #{file}: #{:file.format_error(reason)}"}
      end
    after
      File.rm_rf(staging)
    end
  end

  defp temp_path do
    Path.join(
      System.tmp_dir!(),
      "cleat_pack_#{System.system_time(:millisecond)}_#{:erlang.unique_integer([:positive])}.tar.gz"
    )
  end
end
