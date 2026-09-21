defmodule Cleat.Commands.Servers do
  @moduledoc false

  alias Cleat.{Client, Commands, Output}
  alias Cleat.Commands.ServersLogs

  @usage "usage: cleat servers list | cleat servers show ID | cleat servers logs ID [--unit U] [--tail N] [--since S] [--grep T] [--follow] | cleat servers create --name N --ip IP [--ssh-key-file F] | cleat servers provision --name N [--region fsn1] [--bundle cx33] [--mode shared] | cleat servers delete ID --yes | cleat servers sync ID | cleat servers start ID | cleat servers stop ID | cleat servers resize ID [--bundle BUNDLE]"

  def run([], opts), do: list(opts)
  def run(["list"], opts), do: list(opts)
  def run(["show", id], opts), do: show(id, opts)
  def run(["logs", id | _rest], opts), do: ServersLogs.run(id, opts)
  def run(["create"], opts), do: create(opts)
  def run(["provision"], opts), do: provision(opts)
  def run(["delete", id | _rest], opts), do: delete(id, opts)
  def run(["sync", id], opts), do: sync(id, opts)
  def run(["start", id], opts), do: power(id, :start, opts)
  def run(["stop", id], opts), do: power(id, :stop, opts)
  def run(["resize", id | _rest], opts), do: resize(id, opts)
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

  defp create(opts) do
    with {:ok, ssh_key} <- ssh_key(opts) do
      attrs =
        %{
          "name" => opts[:name],
          "host_ip" => opts[:ip],
          "ssh_user" => opts[:ssh_user] || "ubuntu",
          "region" => opts[:region] || "us-east-1",
          "provider" => opts[:provider] || "lightsail"
        }
        |> maybe_put("ssh_private_key", ssh_key)

      case missing(attrs, [{"name", "--name"}, {"host_ip", "--ip"}]) do
        [] ->
          with {:ok, client} <- Commands.client(opts),
               {:ok, body} <- Client.create_server(client, attrs) do
            server = Commands.data(body)

            Output.success(
              "Created server #{server["name"]} (##{server["id"]}) #{server["host_ip"]}"
            )

            :ok
          end

        missing ->
          {:error, "missing required options: #{Enum.join(missing, ", ")}"}
      end
    end
  end

  defp delete(id, opts) do
    if opts[:yes] do
      with {:ok, client} <- Commands.client(opts),
           {:ok, _body} <- Client.delete_server(client, id) do
        Output.success("Deleted server ##{id}")
        :ok
      end
    else
      {:error, "refusing to delete server ##{id}: pass --yes to confirm"}
    end
  end

  defp sync(id, opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.sync_server(client, id) do
      server = Commands.data(body)

      Output.success(
        "Synced server ##{id} → #{server["bundle_name"] || "unknown"} (#{server["instance_status"]})"
      )

      :ok
    end
  end

  defp provision(opts) do
    attrs = %{
      "name" => opts[:name],
      "region" => opts[:region] || "fsn1",
      "bundle_id" => opts[:bundle] || "cx33",
      "deploy_mode" => opts[:mode] || "shared"
    }

    case missing(attrs, [{"name", "--name"}]) do
      [] ->
        with {:ok, client} <- Commands.client(opts),
             {:ok, body} <- Client.provision_server(client, attrs) do
          server = Commands.data(body)
          Output.success("Provisioned #{server["name"]} (##{server["id"]}) #{server["host_ip"]}")
          :ok
        end

      missing ->
        {:error, "missing required options: #{Enum.join(missing, ", ")}"}
    end
  end

  defp resize(id, opts) do
    if is_binary(opts[:bundle]) and opts[:bundle] != "" do
      with {:ok, client} <- Commands.client(opts),
           {:ok, body} <- Client.resize_server(client, id, opts[:bundle]) do
        server = Commands.data(body)
        Output.success("Resized server ##{id} → #{server["bundle_name"] || server["bundle_id"]}")
        :ok
      end
    else
      resize_options(id, opts)
    end
  end

  defp resize_options(id, opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.resize_options(client, id) do
      options = Commands.data(body)

      if opts[:json] do
        Output.json(options)
      else
        rows =
          Enum.map(options, fn o ->
            [
              o["bundle_id"],
              o["bundle_name"],
              o["cpu_count"],
              o["ram_mb"],
              o["disk_gb"],
              o["monthly_price_usd"]
            ]
          end)

        Output.table(rows, ["BUNDLE", "NAME", "vCPU", "RAM MB", "DISK GB", "PRICE"])
      end

      :ok
    end
  end

  defp power(id, action, opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- call_power(client, id, action) do
      server = Commands.data(body)
      verb = if action == :start, do: "Started", else: "Stopped"
      Output.success("#{verb} server ##{id} (#{server["instance_status"]})")
      :ok
    end
  end

  defp call_power(client, id, :start), do: Client.start_server(client, id)
  defp call_power(client, id, :stop), do: Client.stop_server(client, id)

  defp ssh_key(opts) do
    case opts[:ssh_key_file] do
      nil ->
        {:ok, nil}

      path ->
        case File.read(path) do
          {:ok, content} -> {:ok, content}
          {:error, _} -> {:error, "could not read SSH key file: #{path}"}
        end
    end
  end

  defp missing(attrs, required) do
    required
    |> Enum.filter(fn {key, _flag} -> attrs[key] in [nil, ""] end)
    |> Enum.map(fn {_key, flag} -> flag end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
