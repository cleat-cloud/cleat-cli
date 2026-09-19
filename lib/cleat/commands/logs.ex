defmodule Cleat.Commands.Logs do
  @moduledoc false

  alias Cleat.{Client, Commands, Output}

  @poll_interval 3_000

  def run(id, opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.get_deployment(client, id) do
      deployment = Commands.data(body)
      log = deployment["log"] || ""
      Output.info(log)

      if opts[:follow] do
        follow(client, id, deployment["status"], log)
      else
        :ok
      end
    end
  end

  defp follow(client, id, status, printed) do
    if status in ["queued", "running"] do
      Process.sleep(@poll_interval)

      case Client.get_deployment(client, id) do
        {:ok, body} ->
          deployment = Commands.data(body)
          log = deployment["log"] || ""
          :ok = print_new(log, printed)
          follow(client, id, deployment["status"], log)

        {:error, message} ->
          {:error, message}
      end
    else
      :ok
    end
  end

  defp print_new(log, printed) when byte_size(log) > byte_size(printed) do
    suffix = binary_part(log, byte_size(printed), byte_size(log) - byte_size(printed))
    IO.write(suffix)
  end

  defp print_new(_log, _printed), do: :ok
end
