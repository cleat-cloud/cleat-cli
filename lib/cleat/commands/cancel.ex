defmodule Cleat.Commands.Cancel do
  @moduledoc false

  alias Cleat.{Client, Commands, Output}

  def run(app, opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.cancel_deploy(client, app) do
      deployment = Commands.data(body)

      if opts[:json] do
        Output.json(deployment)
      else
        Output.success(
          "Cancelled deploy ##{deployment["id"]} for #{app} (#{deployment["status"]})"
        )
      end

      :ok
    end
  end
end
