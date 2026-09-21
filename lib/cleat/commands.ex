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
  Resolves the bearer token with the precedence: `--token` (use `-` for stdin),
  `--token-file`, `CLEAT_TOKEN` env var, then the stored config.
  """
  def token(opts) do
    cond do
      opts[:token] == "-" ->
        read_secret_line()

      is_binary(opts[:token]) and opts[:token] != "" ->
        opts[:token]

      is_binary(opts[:token_file]) and opts[:token_file] != "" ->
        read_secret_file(opts[:token_file])

      true ->
        non_empty(System.get_env("CLEAT_TOKEN")) || Config.token()
    end
  end

  @doc """
  Resolves a password from `--password` (use `-` for stdin) or `--password-file`.

  Returns `nil` when not provided, so callers can prompt.
  """
  def password(opts) do
    cond do
      opts[:password] == "-" ->
        read_secret_line()

      is_binary(opts[:password]) and opts[:password] != "" ->
        opts[:password]

      is_binary(opts[:password_file]) and opts[:password_file] != "" ->
        read_secret_file(opts[:password_file])

      true ->
        nil
    end
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

  @doc """
  Base domain for the `--subdomain` shortcut (e.g. `sites.example.com`).

  Resolved from the `--base-domain` flag, then `CLEAT_BASE_DOMAIN`, then the
  stored config.
  """
  def base_domain(opts) do
    opts[:base_domain] || non_empty(System.get_env("CLEAT_BASE_DOMAIN")) ||
      Config.get("base_domain")
  end

  @doc """
  Base domain for static sites. Resolution order: `--sites-base-domain`,
  `CLEAT_SITES_BASE_DOMAIN`, the stored `sites_base_domain`, then the regular
  `base_domain` as a fallback.
  """
  def sites_base_domain(opts) do
    opts[:sites_base_domain] || non_empty(System.get_env("CLEAT_SITES_BASE_DOMAIN")) ||
      Config.sites_base_domain() || base_domain(opts)
  end

  @doc """
  Builds a static-site host from `slug` and the configured sites base domain.

  Returns `{:ok, host}` or `{:error, message}`.
  """
  def static_host(slug, opts) do
    case normalize_base(sites_base_domain(opts)) do
      nil ->
        {:error,
         "no sites base domain configured. Run `cleat config set sites_base_domain " <>
           "sites.example.com`, set CLEAT_SITES_BASE_DOMAIN, or pass --host."}

      base ->
        case Cleat.Slug.from_name(slug) do
          nil -> {:error, "could not derive a slug; pass --slug"}
          sub -> {:ok, "#{sub}.#{base}"}
        end
    end
  end

  @doc """
  Resolves the app host from `--host` or from `--subdomain` + the base domain.

  Returns `{:ok, host}` or `{:error, message}`.
  """
  def host(opts) do
    cond do
      is_binary(opts[:host]) and opts[:host] != "" ->
        {:ok, String.downcase(String.trim(opts[:host]))}

      is_binary(opts[:subdomain]) and opts[:subdomain] != "" ->
        host_from_subdomain(opts[:subdomain], base_domain(opts))

      true ->
        {:error, :missing_host}
    end
  end

  defp host_from_subdomain(subdomain, base) do
    sub = subdomain |> String.trim() |> String.downcase()
    normalized_base = normalize_base(base)

    cond do
      String.contains?(sub, ".") ->
        {:error, "--subdomain must be a single label (use --host for a full domain)"}

      is_nil(normalized_base) ->
        {:error,
         "no base domain configured. Run `cleat config set base_domain sites.example.com`, " <>
           "set CLEAT_BASE_DOMAIN, or pass --base-domain / --host."}

      not Regex.match?(~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/, sub) ->
        {:error, "invalid subdomain #{inspect(subdomain)} (lowercase letters, digits and dashes)"}

      true ->
        {:ok, "#{sub}.#{normalized_base}"}
    end
  end

  defp normalize_base(nil), do: nil

  defp normalize_base(base) do
    case base |> String.trim() |> String.downcase() |> String.trim_trailing(".") do
      "" -> nil
      value -> value
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

  defp read_secret_line do
    case IO.read(:stdio, :line) do
      nil -> nil
      data -> data |> String.trim_trailing("\n") |> String.trim_trailing("\r")
    end
  end

  defp read_secret_file(path) do
    case File.read(path) do
      {:ok, content} -> String.trim(content)
      {:error, _} -> nil
    end
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
