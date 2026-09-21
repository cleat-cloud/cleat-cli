defmodule Cleat.Static do
  @moduledoc """
  Detects whether a drop/deploy target is a plain static site (only HTML).

  A target is static when it is a single `.html`/`.htm` file, or a directory
  with an `index.html` at its root and no build manifest (`package.json`,
  `mix.exs`, `go.mod`). Used to pick a `<slug>.sites...` host automatically.
  """

  @html_exts ~w(.html .htm)
  @build_files ~w(package.json mix.exs go.mod)

  @doc "True when `path` is a plain static site."
  def detect?(path) when is_binary(path) do
    expanded = Path.expand(path)

    cond do
      File.regular?(expanded) -> html_file?(expanded)
      File.dir?(expanded) -> static_dir?(expanded)
      true -> false
    end
  end

  @doc "Derives a DNS-safe slug from a folder or file path."
  def site_slug(path) when is_binary(path) do
    expanded = Path.expand(path)

    base =
      cond do
        File.dir?(expanded) -> Path.basename(expanded)
        File.regular?(expanded) -> Path.rootname(Path.basename(expanded))
        html_file?(expanded) -> Path.rootname(Path.basename(expanded))
        true -> Path.basename(expanded)
      end

    slugify(base)
  end

  defp html_file?(path), do: String.downcase(Path.extname(path)) in @html_exts

  defp static_dir?(dir) do
    File.exists?(Path.join(dir, "index.html")) and
      not Enum.any?(@build_files, &File.exists?(Path.join(dir, &1)))
  end

  defp slugify(name) do
    case name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-") do
      "" -> nil
      slug -> slug
    end
  end
end
