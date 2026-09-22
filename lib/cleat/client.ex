defmodule Cleat.Client do
  @moduledoc """
  Thin HTTP client for the Cleat panel JSON API.
  """

  @receive_timeout 60_000
  @connect_timeout 10_000

  defstruct [:panel_url, :token]

  @type t :: %__MODULE__{panel_url: String.t(), token: String.t() | nil}

  @doc "Builds a client for a panel URL, optionally authenticated."
  def new(panel_url, token \\ nil) when is_binary(panel_url) do
    %__MODULE__{panel_url: normalize_url(panel_url), token: present(token)}
  end

  @doc "Exchanges email/password for a bearer token. Does not need an existing token."
  def create_token(panel_url, email, password, name \\ nil) do
    body =
      %{email: email, password: password}
      |> maybe_put(:name, present(name))

    panel_url
    |> new()
    |> request(:post, "/api/v1/auth/tokens", json: body)
  end

  def me(%__MODULE__{} = client), do: request(client, :get, "/api/v1/me")
  def revoke_token(%__MODULE__{} = client), do: request(client, :delete, "/api/v1/auth/tokens")

  def list_servers(%__MODULE__{} = client), do: request(client, :get, "/api/v1/servers")
  def get_server(client, id), do: request(client, :get, "/api/v1/servers/#{id}")
  def create_server(client, attrs), do: request(client, :post, "/api/v1/servers", json: attrs)
  def delete_server(client, id), do: request(client, :delete, "/api/v1/servers/#{id}")
  def sync_server(client, id), do: request(client, :post, "/api/v1/servers/#{id}/sync")
  def start_server(client, id), do: request(client, :post, "/api/v1/servers/#{id}/start")
  def stop_server(client, id), do: request(client, :post, "/api/v1/servers/#{id}/stop")

  def provision_server(client, attrs),
    do: request(client, :post, "/api/v1/servers/provision", json: attrs)

  def resize_server(client, id, bundle_id),
    do: request(client, :post, "/api/v1/servers/#{id}/resize", json: %{bundle_id: bundle_id})

  def resize_options(client, id),
    do: request(client, :get, "/api/v1/servers/#{id}/resize-options")

  def list_apps(%__MODULE__{} = client), do: request(client, :get, "/api/v1/apps")
  def get_app(client, id_or_slug), do: request(client, :get, "/api/v1/apps/#{id_or_slug}")
  def create_app(client, attrs), do: request(client, :post, "/api/v1/apps", json: attrs)

  def update_app(client, app, attrs),
    do: request(client, :patch, "/api/v1/apps/#{app}", json: attrs)

  def delete_app(client, app), do: request(client, :delete, "/api/v1/apps/#{app}")

  def app_logs(client, app), do: app_logs(client, app, %{})

  def app_logs(%__MODULE__{} = client, app, opts) when is_map(opts) do
    request(client, :get, "/api/v1/apps/#{app}/logs", params: log_params(opts))
  end

  def server_logs(%__MODULE__{} = client, id, opts \\ %{}) when is_map(opts) do
    request(client, :get, "/api/v1/servers/#{id}/logs", params: log_params(opts))
  end

  defp log_params(opts) do
    %{
      "tail" => opts[:tail],
      "since" => opts[:since],
      "grep" => opts[:grep],
      "unit" => opts[:unit]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  def cancel_deploy(client, app),
    do: request(client, :post, "/api/v1/apps/#{app}/cancel", json: %{})

  @doc """
  Uploads a gzipped tarball of a static site (git-less "drop").

  The panel stores the artifact and publishes it on the app's server.
  """
  def create_drop(client, app, tarball_path, ref \\ nil) do
    opts = [
      headers: [{"content-type", "application/gzip"}],
      body: File.read!(tarball_path)
    ]

    opts = if ref, do: Keyword.put(opts, :params, %{ref: ref}), else: opts

    request(client, :post, "/api/v1/apps/#{app}/drops", opts)
  end

  def list_deployments(client, app),
    do: request(client, :get, "/api/v1/apps/#{app}/deployments")

  def create_deployment(client, app, attrs),
    do: request(client, :post, "/api/v1/apps/#{app}/deployments", json: attrs)

  def get_deployment(client, id), do: request(client, :get, "/api/v1/deployments/#{id}")

  def list_env(client, app, reveal? \\ false, branch \\ nil) do
    params =
      [reveal: reveal?, branch: branch]
      |> Enum.reject(fn {_key, value} -> value in [nil, false] end)

    opts = if params == [], do: [], else: [params: params]
    request(client, :get, "/api/v1/apps/#{app}/env", opts)
  end

  def set_env(client, app, attrs),
    do: request(client, :put, "/api/v1/apps/#{app}/env", json: attrs)

  def delete_env(client, app, key, branch \\ nil) do
    opts = if branch in [nil, ""], do: [], else: [params: [branch: branch]]
    request(client, :delete, "/api/v1/apps/#{app}/env/#{key}", opts)
  end

  defp request(%__MODULE__{} = client, method, path, opts \\ []) do
    request = build(client)

    case Req.request(request, [{:method, method}, {:url, path} | opts]) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, error_message(status, body)}

      {:error, reason} ->
        {:error, "request failed: #{inspect(reason)}"}
    end
  end

  defp build(%__MODULE__{panel_url: url, token: token}) do
    [
      base_url: url,
      headers: auth_headers(token),
      retry: false,
      receive_timeout: @receive_timeout,
      connect_options: [timeout: @connect_timeout]
    ]
    |> maybe_put_plug()
    |> Req.new()
  end

  defp maybe_put_plug(opts) do
    case Application.get_env(:cleat_cli, :req_plug) do
      nil -> opts
      plug -> Keyword.put(opts, :plug, plug)
    end
  end

  defp auth_headers(nil), do: []
  defp auth_headers(token), do: [{"authorization", "Bearer #{token}"}]

  defp error_message(status, body) when is_map(body) do
    case body["error"] do
      error when is_binary(error) -> humanize(error) <> error_message_detail(body)
      _ -> "HTTP #{status}"
    end
  end

  defp error_message(status, _body), do: "HTTP #{status}"

  # The panel returns a `message` for actionable errors (e.g. "invalid since
  # (use 30m, 2h, 1d or 2026-09-21)") and a `details` map for field errors.
  defp error_message_detail(%{"details" => details})
       when is_map(details) and map_size(details) > 0 do
    " (" <>
      Enum.map_join(details, ", ", fn {field, messages} ->
        "#{field}: #{Enum.join(List.wrap(messages), ", ")}"
      end) <> ")"
  end

  defp error_message_detail(%{"message" => message}) when is_binary(message) and message != "" do
    " (" <> message <> ")"
  end

  defp error_message_detail(_), do: ""

  defp humanize(error) do
    error
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp normalize_url(url) do
    url |> String.trim() |> String.trim_trailing("/")
  end

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
