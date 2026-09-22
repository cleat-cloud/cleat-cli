defmodule Cleat.Commands.Env do
  @moduledoc false

  alias Cleat.{Client, Commands, Output}
  alias Cleat.Commands.Deploy

  @usage """
  usage:
    cleat env list APP [--branch B] [--reveal]
    cleat env set APP KEY=VALUE [KEY=VALUE ...] [--branch B] [--deploy]
    cleat env unset APP KEY [--branch B] [--deploy]
  """

  def run(["list", app | _rest], opts), do: list(app, opts)

  def run(["set", app | pairs], opts) when pairs != [], do: set(app, pairs, opts)
  def run(["set", _app], _opts), do: {:error, @usage}

  def run(["unset", app, key | _rest], opts), do: unset(app, key, opts)
  def run(["unset" | _rest], _opts), do: {:error, @usage}

  def run(_args, _opts), do: {:error, @usage}

  defp list(app, opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.list_env(client, app, opts[:reveal], opts[:branch]) do
      vars = Commands.data(body)

      if opts[:json] do
        Output.json(vars)
      else
        rows =
          Enum.map(vars, fn var ->
            [branch_label(var["branch"]), var["key"], var["value"], sensitive_label(var)]
          end)

        Output.table(rows, ["BRANCH", "KEY", "VALUE", "SENSITIVE"])

        if opts[:reveal] != true and Enum.any?(vars, & &1["sensitive"]) do
          Output.info("")
          Output.warn("Sensitive values are masked. Re-run with --reveal to show them.")
        end
      end

      :ok
    end
  end

  defp set(app, pairs, opts) do
    with {:ok, vars} <- parse_pairs(pairs),
         {:ok, client} <- Commands.client(opts),
         {:ok, _body} <- Client.set_env(client, app, set_attrs(vars, opts)) do
      Output.success("Set #{map_size(vars)} variable(s) on #{app}#{scope_suffix(opts)}")
      maybe_deploy(app, opts)
    end
  end

  defp unset(app, key, opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, _body} <- Client.delete_env(client, app, key, opts[:branch]) do
      Output.success("Unset #{key} on #{app}#{scope_suffix(opts)}")
      maybe_deploy(app, opts)
    end
  end

  defp set_attrs(vars, opts) do
    if opts[:branch] in [nil, ""] do
      %{vars: vars}
    else
      %{vars: vars, branch: opts[:branch]}
    end
  end

  defp scope_suffix(opts) do
    case opts[:branch] do
      branch when branch in [nil, ""] -> " (all branches)"
      branch -> " (branch #{branch})"
    end
  end

  defp branch_label("*"), do: "ALL"
  defp branch_label(nil), do: "ALL"
  defp branch_label(""), do: "ALL"
  defp branch_label(branch), do: branch

  defp maybe_deploy(app, opts) do
    if opts[:deploy] do
      Deploy.run(app, opts)
    else
      Output.info("Run `cleat deploy #{app}` to apply the change on the server.")
      :ok
    end
  end

  defp parse_pairs(pairs) do
    pairs
    |> Enum.reduce_while({:ok, %{}}, fn pair, {:ok, acc} ->
      case String.split(pair, "=", parts: 2) do
        [key, value] when key != "" ->
          {:cont, {:ok, Map.put(acc, key, value)}}

        _ ->
          {:halt, {:error, "expected KEY=VALUE, got: #{pair}"}}
      end
    end)
  end

  defp sensitive_label(%{"sensitive" => true}), do: "yes"
  defp sensitive_label(_), do: "no"
end
