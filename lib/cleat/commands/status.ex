defmodule Cleat.Commands.Status do
  @moduledoc false

  alias Cleat.{Client, Commands, Output}

  def run(app, opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.list_deployments(client, app) do
      deployments = Commands.data(body)

      if opts[:json] do
        Output.json(deployments)
      else
        case deployments do
          [] ->
            Output.info("No deployments yet for #{app}.")

          _ ->
            rows =
              Enum.map(deployments, fn deployment ->
                [
                  deployment["id"],
                  deployment["status"],
                  deployment["git_ref"] || "—",
                  deployment["git_sha"],
                  deployment["triggered_by"],
                  Output.datetime(deployment["inserted_at"])
                ]
              end)

            Output.table(rows, ["ID", "STATUS", "REF", "SHA", "TRIGGER", "CREATED AT"])
        end
      end

      :ok
    end
  end
end
