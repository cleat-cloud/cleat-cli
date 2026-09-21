defmodule Cleat.Commands.ServersLogs do
  @moduledoc false

  alias Cleat.{Client, Commands, Output}

  def run(id, opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.server_logs(client, id, log_opts(opts)) do
      lines = Commands.data(body)["lines"] || []

      if opts[:follow] do
        Output.info(
          if lines == [], do: "No log lines yet. Following…", else: Enum.join(lines, "\n")
        )

        follow(client, id, log_opts(opts), MapSet.new(lines), 0)
      else
        Output.info(if lines == [], do: "No log lines.", else: Enum.join(lines, "\n"))
        :ok
      end
    end
  end

  defp log_opts(opts) do
    %{tail: opts[:tail], since: opts[:since], grep: opts[:grep], unit: opts[:unit]}
  end

  # A live tail uses a fixed interval (not the deploy poller's growing backoff)
  # and a MapSet for dedup, mirroring `cleat apps logs --follow`.
  defp follow(client, id, log_opts, seen, polls) do
    if polls >= max_polls() do
      :ok
    else
      Process.sleep(interval_ms())

      case Client.server_logs(client, id, log_opts) do
        {:ok, body} ->
          lines = Commands.data(body)["lines"] || []
          {fresh, seen} = fresh_lines(lines, seen)
          Enum.each(fresh, &IO.puts/1)
          follow(client, id, log_opts, prune(seen, lines), polls + 1)

        {:error, message} ->
          Output.error(message)
          :ok
      end
    end
  end

  defp fresh_lines(lines, seen) do
    fresh = Enum.reject(lines, &MapSet.member?(seen, &1))
    {fresh, Enum.reduce(lines, seen, &MapSet.put(&2, &1))}
  end

  defp prune(seen, lines) do
    if MapSet.size(seen) > 5_000, do: MapSet.new(lines), else: seen
  end

  defp max_polls, do: Application.get_env(:cleat_cli, :logs_follow_max_polls, :infinity)
  defp interval_ms, do: Application.get_env(:cleat_cli, :logs_follow_interval_ms, 2_000)
end
