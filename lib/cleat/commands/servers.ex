defmodule Cleat.Commands.Servers do
  @moduledoc false

  alias Cleat.{Client, Commands, Output}

  @usage "usage: cleat servers list | cleat servers show ID"

  def run([], opts), do: list(opts)
  def run(["list"], opts), do: list(opts)
  def run(["show", id], opts), do: show(id, opts)
  def run(_args, _opts), do: {:error, @usage}

  defp list(opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.list_servers(client) do
      servers = Commands.data(body)

      if opts[:json] do
        Output.json(servers)
      else
        rows =
          Enum.map(servers, fn server ->
            [
              server["id"],
              server["name"],
              server["host_ip"],
              server["provider"],
              server["deploy_mode"],
              server["instance_status"]
            ]
          end)

        Output.table(rows, ["ID", "NAME", "IP", "PROVIDER", "MODE", "STATUS"])
      end

      :ok
    end
  end

  defp show(id, opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.get_server(client, id) do
      server = Commands.data(body)

      if opts[:json] do
        Output.json(server)
      else
        Output.table(
          [
            ["ID", server["id"]],
            ["Name", server["name"]],
            ["Host IP", server["host_ip"]],
            ["SSH user", server["ssh_user"]],
            ["Region", server["region"]],
            ["Provider", server["provider"]],
            ["Deploy mode", server["deploy_mode"]],
            ["Status", server["instance_status"]],
            ["Bundle", server["bundle_name"]],
            ["vCPU", server["cpu_count"]],
            ["RAM (MB)", server["ram_mb"]],
            ["Disk (GB)", server["disk_gb"]]
          ],
          ["Field", "Value"]
        )
      end

      :ok
    end
  end
end
