defmodule Cleat.CLI do
  @moduledoc """
  Escript entrypoint for the `cleat` command-line interface.
  """

  alias Cleat.Commands.{
    Apps,
    Cancel,
    Completions,
    Config,
    Deploy,
    Drop,
    Env,
    Init,
    Login,
    Logout,
    Logs,
    Servers,
    Status,
    Whoami
  }

  alias Cleat.Output

  @version Mix.Project.config()[:version]

  @switches [
    panel: :string,
    token: :string,
    email: :string,
    password: :string,
    token_file: :string,
    password_file: :string,
    name: :string,
    json: :boolean,
    ref: :string,
    watch: :boolean,
    follow: :boolean,
    reveal: :boolean,
    deploy: :boolean,
    auto_deploy: :boolean,
    server: :string,
    repo: :string,
    app: :string,
    host: :string,
    subdomain: :string,
    base_domain: :string,
    sites_base_domain: :string,
    ip: :string,
    region: :string,
    provider: :string,
    ssh_user: :string,
    ssh_key_file: :string,
    bundle: :string,
    mode: :string,
    slug: :string,
    runtime: :string,
    binaries: :string,
    port: :integer,
    yes: :boolean,
    tail: :integer,
    since: :string,
    grep: :string,
    unit: :string,
    release_name: :string,
    systemd_unit: :string,
    release_path: :string,
    build_dir: :string,
    build_command: :string,
    start_command: :string,
    node_version: :string,
    ruby_version: :string,
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
  defp dispatch(["mcp"], _opts), do: Cleat.MCP.Server.run()
  defp dispatch(["config" | rest], opts), do: run(Config.run(rest, opts))
  defp dispatch(["completions" | rest], opts), do: run(Completions.run(rest, opts))
  defp dispatch(["servers" | rest], opts), do: run(Servers.run(rest, opts))
  defp dispatch(["apps" | rest], opts), do: run(Apps.run(rest, opts))
  defp dispatch(["env" | rest], opts), do: run(Env.run(rest, opts))

  defp dispatch(["deploy" | rest], opts), do: run(Deploy.run(List.first(rest), opts))
  defp dispatch(["drop" | rest], opts), do: run(Drop.run(rest, opts))
  defp dispatch(["cancel", app | _rest], opts), do: run(Cancel.run(app, opts))
  defp dispatch(["cancel"], _opts), do: fail("usage: cleat cancel APP")

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

  @doc false
  def usage do
    """
    cleat #{@version} — deploy and manage apps on a Cleat panel

    Usage: cleat <command> [options]

    Auth
      login [--panel URL] [--email EMAIL]   Store a panel token (~/.config/cleat)
      logout                                Revoke and clear the stored token
      whoami                                Show the authenticated user and tenant

    Project
      init                                  Write .cleat_deploy/deploy.json
      mcp                                    Run as an MCP server on stdio
                                             (register: claude mcp add cleat -- cleat mcp)
      config [list|get|set|unset]           Show or edit CLI config
      completions bash|zsh                  Print a shell completion script

    Resources
      servers list                          List servers
      servers show ID                       Show one server
      servers create --name N --ip IP \\
        [--ssh-key-file F]                  Register a server
      servers provision --name N \\
        [--region fsn1] [--bundle cx33]     Create a Hetzner VM
      servers resize ID [--bundle B]        Resize (no --bundle: list options)
      servers sync ID                       Refresh cloud specs
      servers start ID                      Power the VM on
      servers stop ID                       Power the VM off
      servers delete ID --yes               Delete a server
      apps list                             List apps
      apps show APP                         Show one app (id or slug)
      apps create --name N --repo O/R \\
        --host H --server ID [--runtime R]   Create an app
      apps update APP [--branch B] \\
        [--auto-deploy|--no-auto-deploy] \\
        [--host H] [--port N] [--repo O/R] \\
        [--runtime R]                       Edit repo / branch / auto-deploy / host / port / runtime
      apps logs APP [--tail N] [--since S] [--grep T] [--follow]
                                            Runtime logs (systemd unit)
      servers logs ID [--unit U] [--tail N] [--since S] [--grep T] [--follow]
                                            Server logs for a unit

    Environment
      env list APP [--reveal]               List env vars (secrets masked)
      env set APP K=V [K=V ...] [--deploy]  Upsert env vars
      env unset APP KEY [--deploy]          Delete an env var

    Deployments
      deploy APP [--ref BRANCH] [--watch]   Trigger a deploy (id or slug)
      deploy --repo owner/repo --server ID \\
        --host H [--branch B] [--runtime R] [--watch]
                                            Register if needed, then deploy
      drop [DIR|FILE] --app APP [--watch]   Publish a folder or file (no git)
      drop [DIR|FILE] --server ID \\
        [--host H] [--slug S] [--watch]     Register if needed, then drop
                                            (plain static sites use <slug>.<sites_base_domain>)
      cancel APP                            Cancel the active deploy
      status APP                            List recent deployments for an app
      logs DEPLOYMENT_ID [--follow]         Print a deployment's build log

    Global options
      --panel URL      Panel base URL (env CLEAT_PANEL_URL)
      --token TOKEN    Bearer token (env CLEAT_TOKEN)
      --host HOST      Full app domain (e.g. landing.sites.example.com)
      --subdomain NAME Shortcut: NAME.<base_domain> (env CLEAT_BASE_DOMAIN)
      --base-domain D  Base domain for --subdomain
      --sites-base-domain D  Base domain for static sites (env CLEAT_SITES_BASE_DOMAIN)
      --json           Machine-readable output      -h, --help       Show this help
      -v, --version    Show the CLI version
    """
  end
end
