defmodule Cleat.Commands.Deploy do
  @moduledoc false

  alias Cleat.{Client, Commands, Output}

  @poll_interval 3_000

  def run(app, opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.create_deployment(client, app, %{git_ref: opts[:ref]}) do
      deployment = Commands.data(body)

      if opts[:json] do
        Output.json(deployment)
      else
        Output.success("Deploy ##{deployment["id"]} queued for #{app} (#{deployment["status"]})")
      end

      if opts[:watch], do: watch(client, deployment["id"]), else: :ok
    end
  end

  defp watch(client, id) do
    loop(client, id, nil)
  end

  defp loop(client, id, last_status) do
    case Client.get_deployment(client, id) do
      {:ok, body} ->
        deployment = Commands.data(body)
        status = deployment["status"]

        if status != last_status, do: Output.info("→ #{status}")

        cond do
          status == "success" ->
            Output.success("Deploy ##{id} succeeded")
            print_log(deployment)
            :ok

          status == "failed" ->
            print_log(deployment)
            {:error, "deploy ##{id} failed"}

          true ->
            Process.sleep(@poll_interval)
            loop(client, id, status)
        end

      {:error, message} ->
        {:error, message}
    end
  end

  defp print_log(%{"log" => log}) when is_binary(log) and log != "" do
    Output.info("")
    Output.info(log)
  end

  defp print_log(_), do: :ok
end
