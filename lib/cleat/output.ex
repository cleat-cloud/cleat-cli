defmodule Cleat.Output do
  @moduledoc """
  Human-friendly and machine-readable output helpers.
  """

  @doc "Prints a plain informational line."
  def info(message), do: IO.puts(message)

  @doc "Prints a success line."
  def success(message), do: IO.puts("✓ " <> message)

  @doc "Prints a warning line."
  def warn(message), do: IO.puts("! " <> message)

  @doc "Prints an error line to stderr."
  def error(message), do: IO.puts(:stderr, "error: " <> message)

  @doc "Prints a JSON document."
  def json(data), do: IO.puts(Jason.encode!(data, pretty: true))

  @doc """
  Prints an aligned text table.

  `headers` is a list of strings; `rows` is a list of equal-length lists.
  """
  def table([], headers) do
    IO.puts(Enum.join(headers, "  "))
  end

  def table(rows, headers) when is_list(rows) and is_list(headers) do
    string_rows = Enum.map(rows, &Enum.map(&1, fn cell -> cell_to_string(cell) end))
    widths = column_widths([headers | string_rows])

    IO.puts(render_row(headers, widths))
    IO.puts(Enum.map_join(widths, "  ", &String.duplicate("-", &1)))
    Enum.each(string_rows, fn row -> IO.puts(render_row(row, widths)) end)
  end

  @doc "Formats a `DateTime` as `YYYY-MM-DD HH:MM:SS`, or `—` when nil."
  def datetime(nil), do: "—"

  def datetime(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> NaiveDateTime.to_string()
    |> String.replace("T", " ")
  end

  def datetime(value) when is_binary(value), do: value
  def datetime(_), do: "—"

  defp column_widths(rows) do
    rows
    |> Enum.zip()
    |> Enum.map(fn column ->
      column
      |> Tuple.to_list()
      |> Enum.map(&String.length/1)
      |> Enum.max(fn -> 0 end)
    end)
  end

  defp render_row(row, widths) do
    row
    |> Enum.with_index()
    |> Enum.map_join("  ", fn {cell, index} ->
      String.pad_trailing(cell, Enum.at(widths, index, String.length(cell)))
    end)
  end

  defp cell_to_string(nil), do: ""
  defp cell_to_string(value) when is_binary(value), do: value
  defp cell_to_string(value), do: to_string(value)
end
