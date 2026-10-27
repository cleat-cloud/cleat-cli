defmodule Cleat.MCP.Tools.Support do
  @moduledoc false

  alias Cleat.{Client, Commands}

  @doc "Builds a panel client from the tool arguments and hands it to `fun`."
  def with_client(args, fun) do
    with :ok <- validate_token(args),
         {:ok, client} <- Commands.client(opts(args)) do
      fun.(client)
    end
  end

  def json(data), do: Jason.encode!(data)

  def data_text(body), do: json(Commands.data(body))

  def compact_params(params) do
    params
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  def present?(args, key) do
    case Map.get(args, key) do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  def normalize_host(nil), do: nil

  def normalize_host(host) when is_binary(host) do
    host |> String.trim() |> String.downcase() |> String.trim_trailing(".")
  end

  @doc """
  Resolves a server selector (id, name or slug) to the id the API expects.
  """
  def resolve_server_id(_client, server) when not is_binary(server) or server == "",
    do: {:error, "server is required"}

  def resolve_server_id(client, server) do
    trimmed = String.trim(server)

    cond do
      trimmed == "" ->
        {:error, "server is required"}

      numeric_server_id?(trimmed) ->
        {:ok, trimmed}

      true ->
        with {:ok, body} <- Client.list_servers(client) do
          match_server(List.wrap(Commands.data(body)), trimmed)
        end
    end
  end

  defp numeric_server_id?(value), do: Regex.match?(~r/^\d+$/, value)

  defp match_server(servers, query) do
    needle = String.downcase(query)

    found =
      Enum.find(servers, fn server ->
        id = server |> Map.get("id") |> to_string() |> String.downcase()
        name = server |> Map.get("name") |> to_string() |> String.downcase()
        slug = server |> Map.get("slug") |> to_string() |> String.downcase()

        id == needle or name == needle or (slug != "" and slug == needle)
      end)

    case found do
      nil ->
        listing =
          servers
          |> Enum.map(fn server -> "#{Map.get(server, "id")} (#{Map.get(server, "name")})" end)
          |> Enum.join(", ")

        listing = if listing == "", do: "none", else: listing

        {:error,
         ~s|unknown server "#{query}". Use a servers_list id (e.g. 5) — servers: #{listing}|}

      server ->
        {:ok, server |> Map.get("id") |> to_string()}
    end
  end

  defp opts(args) do
    %{}
    |> maybe_put(:panel, args["panel"])
    |> maybe_put(:token, args["token"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp validate_token(%{"token" => "-"}),
    do: {:error, "token '-' (stdin) is not supported over MCP"}

  defp validate_token(_args), do: :ok
end
