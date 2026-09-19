defmodule Cleat.Commands.Logout do
  @moduledoc false

  alias Cleat.{Client, Commands, Config, Output}

  def run(opts) do
    case Commands.client(opts) do
      {:ok, client} ->
        case Client.revoke_token(client) do
          {:ok, _body} -> Output.success("Token revoked on the panel")
          {:error, message} -> Output.warn("Could not revoke token remotely: #{message}")
        end

      {:error, _message} ->
        :ok
    end

    Config.delete("token")
    Config.delete("user")
    Config.delete("tenant")
    Output.info("Local credentials cleared")
    :ok
  end
end
