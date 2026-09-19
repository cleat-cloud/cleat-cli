defmodule Cleat.Commands.Login do
  @moduledoc false

  alias Cleat.{Client, Commands, Config, Output}

  def run(opts) do
    panel = Commands.panel_url(opts)

    if is_nil(panel) do
      {:error, "missing panel URL. Pass --panel URL or set CLEAT_PANEL_URL."}
    else
      email = opts[:email] || prompt("Email: ")
      password = opts[:password] || Commands.read_password("Password: ")

      case Client.create_token(panel, email, password, opts[:name] || default_name()) do
        {:ok, body} ->
          store(panel, body)
          Output.success("Logged in as #{body["user"]["email"]} (#{body["tenant"]["name"]})")
          Output.info("Token stored in #{Config.path()}")
          :ok

        {:error, message} ->
          {:error, message}
      end
    end
  end

  defp store(panel, body) do
    Config.save(%{
      "panel_url" => Client.new(panel).panel_url,
      "token" => body["token"],
      "user" => body["user"],
      "tenant" => body["tenant"]
    })
  end

  defp prompt(label) do
    case IO.gets(label) do
      nil -> ""
      value -> String.trim_trailing(value, "\n")
    end
  end

  defp default_name do
    case :inet.gethostname() do
      {:ok, hostname} -> "cleat-cli on #{hostname}"
      _ -> "cleat-cli"
    end
  end
end
