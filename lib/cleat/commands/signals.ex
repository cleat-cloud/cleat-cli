defmodule Cleat.Commands.Signals do
  @moduledoc """
  `cleat signals` — health, metrics, alerts and traces from the panel.
  """

  alias Cleat.{Client, Commands, Output}

  @usage """
  usage:
    cleat signals health [APP]
    cleat signals metrics APP [--range 1h|6h|24h|1d]
    cleat signals alerts [list]
    cleat signals alerts ack ID
    cleat signals traces APP [--trace-id ID] [--service NAME]
    cleat signals sampling APP [--rate 0.0..1.0]
  """

  def run(["health" | rest], opts), do: health(rest, opts)
  def run(["metrics", app | _rest], opts), do: metrics(app, opts)
  def run(["metrics"], _opts), do: {:error, @usage}
  def run(["alerts"], opts), do: alerts(opts)
  def run(["alerts", "list" | _rest], opts), do: alerts(opts)
  def run(["alerts", "ack", id | _rest], opts), do: ack(id, opts)
  def run(["traces", app | _rest], opts), do: traces(app, opts)
  def run(["traces"], _opts), do: {:error, @usage}
  def run(["sampling", app | _rest], opts), do: sampling(app, opts)
  def run(["sampling"], _opts), do: {:error, @usage}
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

  defp traces(app, opts) do
    params =
      compact(%{
        "app" => app,
        "trace_id" => opts[:trace_id],
        "service" => opts[:service]
      })

    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.signals_traces(client, params) do
      data = Commands.data(body)
      if opts[:json], do: Output.json(data), else: print_traces(data)
      :ok
    end
  end

  defp sampling(app, opts) do
    with {:ok, client} <- Commands.client(opts) do
      result =
        case opts[:rate] do
          nil ->
            Client.signals_sampling(client, compact(%{"app" => app}))

          rate ->
            Client.update_signals_sampling(client, %{"app" => app, "rate" => rate})
        end

      with {:ok, body} <- result do
        data = Commands.data(body)
        if opts[:json], do: Output.json(data), else: print_sampling(data)
        :ok
      end
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

  defp print_traces(rows) when is_list(rows) do
    if rows == [] do
      Output.info("No traces in this window.")
    else
      table =
        Enum.map(rows, fn row ->
          [
            row["trace_id"],
            row["root_name"],
            services(row["services"]),
            row["duration_ms"],
            row["span_count"],
            if(row["error"], do: "error", else: "ok")
          ]
        end)

      Output.table(table, ["TRACE", "ROOT", "SERVICES", "MS", "SPANS", "STATUS"])
    end
  end

  defp print_traces(%{} = detail) do
    trace = detail["trace"] || %{}
    Output.info("#{trace["trace_id"]}  #{trace["root_name"]}  #{trace["duration_ms"]}ms")

    Enum.each(detail["spans"] || [], fn span ->
      indent = String.duplicate("  ", span["depth"] || 0)
      Output.info("#{indent}#{span["name"]}  #{span["service_name"]}  #{span["duration_ms"]}ms")
    end)

    print_service_map(detail["service_map"])
    print_trace_logs(detail["logs"] || [])
  end

  defp print_service_map(%{"edges" => edges}) when is_list(edges) and edges != [] do
    Output.info("MAP  #{Enum.map_join(edges, ",", &edge_label/1)}")
  end

  defp print_service_map(_), do: :ok

  defp print_trace_logs([]), do: :ok

  defp print_trace_logs(logs) do
    Enum.each(logs, fn log ->
      Output.info("LOG  #{log["id"]}  #{log["message"]}")
    end)
  end

  defp print_sampling(data) do
    Output.info("#{data["slug"]}  rate=#{data["trace_sample_rate"]}")
  end

  defp services(list) when is_list(list), do: Enum.join(list, ",")
  defp services(_), do: "—"

  defp edge_label(%{"from" => from, "to" => to, "count" => count}), do: "#{from}→#{to}(#{count})"
  defp edge_label(other), do: inspect(other)
end
