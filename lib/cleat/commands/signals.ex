defmodule Cleat.Commands.Signals do
  @moduledoc """
  `cleat signals` — health, metrics and alerts from the panel (Corte 02).
  """

  alias Cleat.{Client, Commands, Output}

  @usage """
  usage:
    cleat signals health [APP]
    cleat signals metrics APP [--range 1h|6h|24h|1d]
    cleat signals alerts [list]
    cleat signals alerts ack ID
  """

  def run(["health" | rest], opts), do: health(rest, opts)
  def run(["metrics", app | _rest], opts), do: metrics(app, opts)
  def run(["metrics"], _opts), do: {:error, @usage}
  def run(["alerts"], opts), do: alerts(opts)
  def run(["alerts", "list" | _rest], opts), do: alerts(opts)
  def run(["alerts", "ack", id | _rest], opts), do: ack(id, opts)
  def run(_args, _opts), do: {:error, @usage}

  defp health(args, opts) do
    with {:ok, app} <- optional_app(args, opts),
         {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.signals_health(client, compact(%{"app" => app})) do
      rows = Commands.data(body)
      if opts[:json], do: Output.json(rows), else: print_health(rows)
      :ok
    end
  end

  defp metrics(app, opts) do
    params = compact(%{"app" => app, "range" => opts[:range]})

    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.signals_metrics(client, params) do
      data = Commands.data(body)
      if opts[:json], do: Output.json(data), else: print_metrics(data)
      :ok
    end
  end

  defp alerts(opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.signals_alerts(client) do
      rows = Commands.data(body)
      if opts[:json], do: Output.json(rows), else: print_alerts(rows)
      :ok
    end
  end

  defp ack(id, opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.ack_signal_alert(client, id) do
      alert = Commands.data(body)

      if opts[:json] do
        Output.json(alert)
      else
        Output.success("Acked alert #{alert["id"] || id} on #{alert["slug"] || "app"}")
      end

      :ok
    end
  end

  defp optional_app([], opts), do: {:ok, opts[:app]}
  defp optional_app([app], _opts) when is_binary(app), do: {:ok, app}
  defp optional_app(_args, _opts), do: {:error, @usage}

  defp compact(params) do
    params
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp print_health([]) do
    Output.info("No applications matched.")
  end

  defp print_health(rows) do
    table =
      Enum.map(rows, fn row ->
        [
          row["slug"],
          row["status"],
          reasons(row["reasons"]),
          release(row["preceding_release"]),
          row["error_count"]
        ]
      end)

    Output.table(table, ["APP", "STATUS", "REASONS", "RELEASE", "ERRORS"])
  end

  defp print_metrics(data) do
    red = data["red"] || %{}
    host = data["host"] || %{}
    markers = data["deploy_markers"] || []

    Output.info("#{data["slug"]}  range=#{data["range"]}")

    Output.info(
      "RED  errors=#{red["errors"]}  logs=#{red["logs"]}  error_rate=#{red["error_rate"]}  latency=#{dash(red["latency_ms"])}"
    )

    Output.info(
      "HOST  cpu=#{dash(host["cpu"])}  memory=#{dash(host["memory"])}  disk=#{dash(host["disk"])}  restarts=#{host["restarts"]}"
    )

    Output.info("MARKERS  #{markers_label(markers)}")
  end

  defp print_alerts([]) do
    Output.info("No open alerts.")
  end

  defp print_alerts(rows) do
    table =
      Enum.map(rows, fn row ->
        [row["id"], row["slug"], row["rule"], row["status"], row["message"]]
      end)

    Output.table(table, ["ID", "APP", "RULE", "STATUS", "MESSAGE"])
  end

  defp reasons(list) when is_list(list) and list != [], do: Enum.join(list, ",")
  defp reasons(_), do: "—"

  defp release(%{"git_sha" => sha}) when is_binary(sha), do: String.slice(sha, 0, 8)
  defp release(_), do: "—"

  defp dash(nil), do: "—"
  defp dash(value), do: value

  defp markers_label([]), do: "—"

  defp markers_label(markers) do
    Enum.map_join(markers, ",", fn marker -> marker["git_sha"] || inspect(marker) end)
  end
end
