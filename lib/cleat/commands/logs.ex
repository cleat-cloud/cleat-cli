defmodule Cleat.Commands.Logs do
  @moduledoc false

  alias Cleat.{Client, Commands, Output, Poller}

  def run(id, opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.get_deployment(client, id) do
      deployment = Commands.data(body)
      log = deployment["log"] || ""
      Output.info(log)

      if opts[:follow] do
        follow(client, id, log)
      else
        :ok
      end
    end
  end

  defp follow(client, id, printed) do
    fetch = fn -> Client.get_deployment(client, id) end

    step = fn body, printed ->
      deployment = Commands.data(body)
      log = deployment["log"] || ""
      :ok = print_new(log, printed)

      if deployment["status"] in ["queued", "running"] do
        {:continue, log}
      else
        :done
      end
    end

    Poller.poll(fetch, step, printed)
  end

  defp print_new(log, printed) when byte_size(log) > byte_size(printed) do
    suffix = binary_part(log, byte_size(printed), byte_size(log) - byte_size(printed))
    IO.write(suffix)
  end

  defp print_new(_log, _printed), do: :ok
end
