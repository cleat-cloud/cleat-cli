defmodule Cleat.Commands.ServersLogs do
  @moduledoc false

  alias Cleat.{Client, Commands, Output, Poller}

  def run(id, opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.server_logs(client, id, log_opts(opts)) do
      lines = Commands.data(body)["lines"] || []
      Output.info(Enum.join(lines, "\n"))

      if opts[:follow], do: follow(client, id, lines, opts), else: :ok
    end
  end

  defp log_opts(opts) do
    %{
      tail: opts[:tail],
      since: opts[:since],
      grep: opts[:grep],
      unit: opts[:unit]
    }
  end

  defp follow(client, id, printed, opts) do
    fetch = fn -> Client.server_logs(client, id, log_opts(opts)) end

    step = fn body, printed ->
      lines = Commands.data(body)["lines"] || []
      fresh = Enum.reject(lines, &(&1 in printed))
      Enum.each(fresh, &IO.puts/1)
      {:continue, lines}
    end

    Poller.poll(fetch, step, printed, poll_opts(opts))
  end

  defp poll_opts(opts) when is_list(opts), do: opts
  defp poll_opts(_opts), do: []
end
