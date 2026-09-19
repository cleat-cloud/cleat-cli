defmodule Cleat.Commands do
  @moduledoc """
  Shared helpers for CLI commands: client resolution and output formatting.
  """

  alias Cleat.{Client, Config}

  @doc """
  Resolves the panel URL with the precedence: `--panel` flag, `CLEAT_PANEL_URL`
  env var, then the stored config.
  """
  def panel_url(opts) do
    opts[:panel] || non_empty(System.get_env("CLEAT_PANEL_URL")) || Config.panel_url()
  end

  @doc """
  Resolves the bearer token with the precedence: `--token` flag, `CLEAT_TOKEN`
  env var, then the stored config.
  """
  def token(opts) do
    opts[:token] || non_empty(System.get_env("CLEAT_TOKEN")) || Config.token()
  end

  @doc "Builds an authenticated client or returns an actionable error."
  def client(opts) do
    panel = panel_url(opts)
    token = token(opts)

    cond do
      is_nil(panel) ->
        {:error,
         "no panel configured. Run `cleat login --panel https://panel.example.com` " <>
           "or set CLEAT_PANEL_URL."}

      is_nil(token) ->
        {:error, "not authenticated. Run `cleat login` or set CLEAT_TOKEN."}

      true ->
        {:ok, Client.new(panel, token)}
    end
  end

  @doc "Reads a password without echoing it when possible."
  def read_password(prompt) do
    IO.write(prompt)

    case safe_get_password() do
      {:ok, password} ->
        IO.write("\n")
        password

      :error ->
        IO.gets("")
        |> case do
          nil -> ""
          value -> String.trim_trailing(value, "\n")
        end
    end
  end

  @doc "Returns the `data` payload from an API response."
  def data(%{"data" => data}), do: data
  def data(other), do: other

  defp safe_get_password do
    case :io.get_password() do
      password when is_list(password) -> {:ok, List.to_string(password)}
      password when is_binary(password) -> {:ok, password}
      _ -> :error
    end
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp non_empty(nil), do: nil

  defp non_empty(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp non_empty(_), do: nil
end
