defmodule Cleat.CLI do
  @moduledoc """
  Escript entrypoint for the `cleat` command-line interface.
  """

  alias Cleat.Commands.{Apps, Deploy, Init, Login, Logout, Logs, Servers, Status, Whoami}
  alias Cleat.Output

  @version Mix.Project.config()[:version]

  @switches [
    panel: :string,
    token: :string,
    email: :string,
    password: :string,
    name: :string,
    json: :boolean,
    ref: :string,
    watch: :boolean,
    follow: :boolean,
    server: :string,
    repo: :string,
    branch: :string,
    host: :string,
    slug: :string,
    runtime: :string,
    binaries: :string,
    port: :integer,
    yes: :boolean,
    release_name: :string,
    systemd_unit: :string,
    release_path: :string,
    build_dir: :string,
    memory_max_mb: :integer,
    caddy_mode: :string,
    caddy_listen_port: :integer,
    solo_server: :boolean,
    help: :boolean,
    version: :boolean
  ]

  @aliases [p: :panel, h: :help, v: :version]

  def main(argv) do
    {opts, args, invalid} = OptionParser.parse(argv, strict: @switches, aliases: @aliases)

    cond do
      invalid != [] ->
        fail("unknown options: #{format_invalid(invalid)}")

      opts[:help] ->
        help()

      opts[:version] ->
        version()

      true ->
        dispatch(args, opts)
    end
  end

  defp dispatch([], _opts), do: help()
  defp dispatch(["help"], _opts), do: help()
  defp dispatch(["version"], _opts), do: version()
  defp dispatch(["login"], opts), do: run(Login.run(opts))
  defp dispatch(["logout"], opts), do: run(Logout.run(opts))
  defp dispatch(["whoami"], opts), do: run(Whoami.run(opts))
  defp dispatch(["init"], opts), do: run(Init.run(opts))
  defp dispatch(["servers" | rest], opts), do: run(Servers.run(rest, opts))
  defp dispatch(["apps" | rest], opts), do: run(Apps.run(rest, opts))

  defp dispatch(["deploy", app | _rest], opts), do: run(Deploy.run(app, opts))
  defp dispatch(["deploy"], _opts), do: fail("usage: cleat deploy APP [--ref BRANCH] [--watch]")

  defp dispatch(["status", app | _rest], opts), do: run(Status.run(app, opts))
  defp dispatch(["status"], _opts), do: fail("usage: cleat status APP")

  defp dispatch(["logs", id | _rest], opts), do: run(Logs.run(id, opts))
  defp dispatch(["logs"], _opts), do: fail("usage: cleat logs DEPLOYMENT_ID [--follow]")

  defp dispatch([command | _rest], _opts), do: fail("unknown command: #{command}")

  defp run(:ok), do: System.halt(0)
  defp run({:error, message}), do: fail(message)

  defp fail(message) do
    Output.error(message)
    System.halt(1)
  end

  defp help do
    IO.puts(usage())
    System.halt(0)
  end

  defp version do
    IO.puts("cleat #{@version}")
    System.halt(0)
  end

  defp format_invalid(invalid) do
    Enum.map_join(invalid, ", ", fn {switch, _value} -> switch end)
  end

  defp usage do
    """
    cleat #{@version} — deploy and manage apps on a Cleat panel

    Usage: cleat <command> [options]

    Auth
      login [--panel URL] [--email EMAIL]   Store a panel token (~/.config/cleat)
      logout                                Revoke and clear the stored token
      whoami                                Show the authenticated user and tenant

    Project
      init                                  Write .cleat_deploy/deploy.json

    Resources
      servers list                          List servers
      servers show ID                       Show one server
      apps list                             List apps
      apps show APP                         Show one app (id or slug)
      apps create --name N --repo O/R \\
        --host H --server ID                Create an app

    Deployments
      deploy APP [--ref BRANCH] [--watch]   Trigger a deploy (id or slug)
      status APP                            List recent deployments for an app
      logs DEPLOYMENT_ID [--follow]         Print a deployment's build log

    Global options
      --panel URL      Panel base URL (env CLEAT_PANEL_URL)
      --token TOKEN    Bearer token (env CLEAT_TOKEN)
      --json           Machine-readable output
      -h, --help       Show this help
      -v, --version    Show the CLI version
    """
  end
end
