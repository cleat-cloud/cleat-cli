defmodule Cleat.Static do
  @moduledoc """
  Detects whether a drop/deploy target is a plain static site (only HTML).

  A target is static when it is a single `.html`/`.htm` file, or a directory
  with an `index.html` at its root and no build manifest (`package.json`,
  `mix.exs`, `go.mod`). Used to pick a `<slug>.sites...` host automatically.

  Build manifests are only checked at the root of the directory; a manifest
  nested deeper does not make the target non-static.
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

  @doc """
  Derives a DNS-safe slug from a folder or file path.

  A directory uses its base name; a `.html`/`.htm` file uses its rootname.
  Returns `nil` when the name has no usable characters (e.g. a folder named
  `---`). A `.html`/`.htm` path need not exist: it is treated by extension, so
  a path to a not-yet-created file still yields its rootname.
  """
  def site_slug(path) when is_binary(path) do
    expanded = Path.expand(path)

    base =
      cond do
        File.dir?(expanded) ->
          Path.basename(expanded)

        # `File.regular?/1` is false for a path that does not exist yet, so we
        # also match by extension to support non-existent `.html` paths.
        File.regular?(expanded) or html_file?(expanded) ->
          Path.rootname(Path.basename(expanded))

        true ->
          Path.basename(expanded)
      end

    Cleat.Slug.from_name(base)
  end

  defp html_file?(path), do: String.downcase(Path.extname(path)) in @html_exts

  defp static_dir?(dir) do
    File.regular?(Path.join(dir, "index.html")) and
      not Enum.any?(@build_files, &File.exists?(Path.join(dir, &1)))
  end
end
