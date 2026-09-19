defmodule Cleat.Commands.Whoami do
  @moduledoc false

  alias Cleat.{Client, Commands, Output}

  def run(opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.me(client) do
      data = Commands.data(body)

      if opts[:json] do
        Output.json(data)
      else
        Output.table(
          [
            ["User", data["user"]["email"]],
            ["Tenant", data["tenant"]["name"]],
            ["Role", data["role"]],
            ["Panel", Commands.panel_url(opts)]
          ],
          ["Field", "Value"]
        )
      end

      :ok
    end
  end
end
