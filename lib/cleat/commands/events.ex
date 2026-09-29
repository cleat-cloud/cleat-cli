defmodule Cleat.Commands.Events do
  @moduledoc """
  `cleat events` — searches the panel's collected log events.

  This is the stored, correlatable view of logs (observability Corte 01):
  events are enriched by the panel with tenant, app, server, deployment and
  unit, so they can be filtered by app, severity, unit and time window without
  touching the VM.
  """

  alias Cleat.{Client, Commands, Output}

  @usage "usage: cleat events [APP] [--server ID] [--unit U] [--query TEXT] [--severity LEVEL] [--min-severity LEVEL] [--since S] [--until S] [--limit N] [--json]"

  @severities ~w(emerg alert crit err warning notice info debug)

  def run(args, opts) do
    with {:ok, params} <- params(args, opts),
         {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.search_logs(client, params) do
      events = Commands.data(body)

      if opts[:json] do
        Output.json(events)
      else
        print(events)
      end

      :ok
    end
  end

  defp params(args, opts) do
    with {:ok, app} <- app(args, opts),
         {:ok, severity} <- severity(opts[:severity], "--severity"),
         {:ok, min_severity} <- severity(opts[:min_severity], "--min-severity") do
      params = %{
        "app" => app,
        "server" => opts[:server],
        "unit" => opts[:unit],
        "q" => opts[:query],
        "severity" => severity,
        "min_severity" => min_severity,
        "since" => opts[:since],
        "until" => opts[:until],
        "limit" => opts[:limit]
      }

      {:ok, params |> Enum.reject(fn {_key, value} -> value in [nil, ""] end) |> Map.new()}
    end
  end

  defp app([], opts), do: {:ok, opts[:app]}
  defp app([app], _opts) when is_binary(app), do: {:ok, app}
  defp app(_args, _opts), do: {:error, @usage}

  defp severity(value, _flag) when value in [nil, ""], do: {:ok, nil}

  defp severity(value, flag) do
    if value in @severities do
      {:ok, value}
    else
      {:error, "invalid #{flag} (use #{Enum.join(@severities, ", ")})"}
    end
  end

  defp print([]), do: Output.info("No log events matched.")

  defp print(events) do
    rows =
      Enum.map(events, fn event ->
        [
          timestamp(event["occurred_at"]),
          event["severity"],
          event["app_id"] || "—",
          event["unit"] || "—",
          message(event["message"])
        ]
      end)

    Output.table(rows, ["TIME", "SEV", "APP", "UNIT", "MESSAGE"])
  end

  defp timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> Output.datetime(datetime)
      _ -> value
    end
  end

  defp timestamp(_), do: "—"

  defp message(nil), do: ""
  defp message(text), do: text |> String.replace("\n", " ") |> String.slice(0, 120)
end
