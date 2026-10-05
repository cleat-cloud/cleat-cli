defmodule Cleat.Commands.Analytics do
  @moduledoc """
  `cleat analytics` — product usage from the panel.

  `requested` reads Caddy's access log (HTTP hits); `visited` and `show` read
  the pageview sidecar (JS, inject-on only). The two are not interchangeable.
  """

  alias Cleat.{Client, Commands, Output}

  @usage """
  usage:
    cleat analytics requested
    cleat analytics visited
    cleat analytics show APP [--range 24h|7d|90d]
  """

  def run(["requested" | _rest], opts), do: requested(opts)
  def run(["visited" | _rest], opts), do: visited(opts)
  def run(["show", app | _rest], opts), do: show(app, opts)
  def run(["show"], _opts), do: {:error, @usage}
  def run(_args, _opts), do: {:error, @usage}

  defp requested(opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.analytics_requested(client) do
      rows = Commands.data(body)
      if opts[:json], do: Output.json(rows), else: print_requested(rows)
      :ok
    end
  end

  defp visited(opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.analytics_visited(client) do
      rows = Commands.data(body)
      stale? = body["stale"] == true

      if opts[:json] do
        Output.json(%{"data" => rows, "stale" => stale?})
      else
        print_visited(rows, stale?)
      end

      :ok
    end
  end

  defp show(app, opts) do
    params = compact(%{"range" => opts[:range]})

    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.analytics_summary(client, app, params) do
      data = Commands.data(body)
      if opts[:json], do: Output.json(data), else: print_summary(data)
      :ok
    end
  end

  defp print_requested([]) do
    Output.info("No request samples on the active server.")
  end

  defp print_requested(rows) do
    table =
      Enum.map(rows, fn row ->
        [row["slug"], row["host"], row["requests"]]
      end)

    Output.table(table, ["APP", "HOST", "REQUESTS"])
  end

  defp print_visited(rows, stale?) do
    cond do
      stale? and rows == [] ->
        Output.info("Analytics stale: the sidecar did not answer.")

      stale? ->
        Output.info("Analytics stale: the sidecar did not answer, showing the last snapshot.")
        print_visited_rows(rows)

      rows == [] ->
        Output.info("No pageviews in this window.")

      true ->
        print_visited_rows(rows)
    end
  end

  defp print_visited_rows(rows) do
    table =
      Enum.map(rows, fn row ->
        [row["slug"], row["host"], row["pageviews"]]
      end)

    Output.table(table, ["APP", "HOST", "PAGEVIEWS"])
  end

  defp print_summary(data) do
    Output.info(
      "#{data["slug"]}  range=#{data["range"]}  pageviews=#{data["pageviews"]}  uniques=#{data["uniques"]}"
    )

    if data["stale"] do
      Output.info("STALE  the sidecar did not answer — numbers may be missing.")
    end

    print_rows("PATHS", "PATH", data["paths"])
    print_rows("REFERRERS", "REFERRER", data["referrers"])
    print_utm(data["utm"])
  end

  defp print_rows(label, column, rows) do
    rows = rows || []

    if rows == [] do
      Output.info("#{label}  —")
    else
      table = Enum.map(rows, fn row -> [row["path"] || row["referrer"], row["pageviews"]] end)
      Output.table(table, [column, "PAGEVIEWS"])
    end
  end

  defp print_utm(rows) do
    rows = rows || []

    if rows == [] do
      Output.info("UTM  —")
    else
      table =
        Enum.map(rows, fn row ->
          [
            Enum.join(
              [row["source"], row["medium"], row["campaign"]] |> Enum.reject(&is_nil/1),
              "/"
            ),
            row["pageviews"]
          ]
        end)

      Output.table(table, ["SOURCE/MEDIUM/CAMPAIGN", "PAGEVIEWS"])
    end
  end

  defp compact(params) do
    params
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end
end
