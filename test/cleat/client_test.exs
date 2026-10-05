defmodule Cleat.ClientTest do
  use ExUnit.Case, async: false

  alias Cleat.Client

  setup do
    Application.put_env(:cleat_cli, :req_plug, {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:cleat_cli, :req_plug) end)
    :ok
  end

  test "search_logs sends the filters to /api/v1/logs" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/v1/logs"

      assert URI.decode_query(conn.query_string) == %{
               "app" => "my-app",
               "min_severity" => "err"
             }

      Req.Test.json(conn, %{"data" => [%{"id" => 1, "message" => "boom"}]})
    end)

    client = Client.new("https://panel.test", "tok")

    assert {:ok, %{"data" => [%{"id" => 1, "message" => "boom"}]}} =
             Client.search_logs(client, %{"app" => "my-app", "min_severity" => "err"})
  end

  test "signals_health GETs /api/v1/signals/health" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/v1/signals/health"
      assert URI.decode_query(conn.query_string)["app"] == "catalogo"
      Req.Test.json(conn, %{"data" => [%{"slug" => "catalogo", "status" => "healthy"}]})
    end)

    client = Client.new("https://panel.test", "tok")

    assert {:ok, %{"data" => [%{"slug" => "catalogo"}]}} =
             Client.signals_health(client, %{"app" => "catalogo"})
  end

  test "signals_pages GETs /api/v1/signals/pages" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/v1/signals/pages"
      params = URI.decode_query(conn.query_string)
      assert params["app"] == "new-lp"
      assert params["range"] == "24h"
      Req.Test.json(conn, %{"data" => %{"slug" => "new-lp", "requested" => []}})
    end)

    client = Client.new("https://panel.test", "tok")

    assert {:ok, %{"data" => %{"slug" => "new-lp"}}} =
             Client.signals_pages(client, %{"app" => "new-lp", "range" => "24h"})
  end

  test "analytics_requested GETs /api/v1/analytics/requested" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/v1/analytics/requested"
      Req.Test.json(conn, %{"data" => [%{"slug" => "nfe-facil", "requests" => 3}]})
    end)

    client = Client.new("https://panel.test", "tok")

    assert {:ok, %{"data" => [%{"slug" => "nfe-facil"}]}} =
             Client.analytics_requested(client)
  end

  test "analytics_visited GETs /api/v1/analytics/visited" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/v1/analytics/visited"
      Req.Test.json(conn, %{"data" => [], "stale" => true})
    end)

    client = Client.new("https://panel.test", "tok")

    assert {:ok, %{"stale" => true}} = Client.analytics_visited(client)
  end

  test "analytics_summary GETs /api/v1/apps/:id/analytics with the range" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/v1/apps/fagulha-app/analytics"
      assert URI.decode_query(conn.query_string)["range"] == "7d"
      Req.Test.json(conn, %{"data" => %{"slug" => "fagulha-app", "range" => "7d"}})
    end)

    client = Client.new("https://panel.test", "tok")

    assert {:ok, %{"data" => %{"range" => "7d"}}} =
             Client.analytics_summary(client, "fagulha-app", %{"range" => "7d"})
  end

  test "query_app POSTs /api/v1/apps/:id/query" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/v1/apps/new-lp/query"
      assert Jason.decode!(Req.Test.raw_body(conn)) == %{"sql" => "SELECT 1", "limit" => 5}
      Req.Test.json(conn, %{"data" => %{"engine" => "postgres", "rows" => []}})
    end)

    client = Client.new("https://panel.test", "tok")

    assert {:ok, %{"data" => %{"engine" => "postgres"}}} =
             Client.query_app(client, "new-lp", %{"sql" => "SELECT 1", "limit" => 5})
  end

  test "signals_traces GETs /api/v1/signals/traces" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/v1/signals/traces"
      params = URI.decode_query(conn.query_string)
      assert params["app"] == "catalogo"
      assert params["service"] == "payment"
      Req.Test.json(conn, %{"data" => [%{"trace_id" => "abc"}]})
    end)

    client = Client.new("https://panel.test", "tok")

    assert {:ok, %{"data" => [%{"trace_id" => "abc"}]}} =
             Client.signals_traces(client, %{"app" => "catalogo", "service" => "payment"})
  end

  test "update_signals_sampling PATCHes /api/v1/signals/sampling" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "PATCH"
      assert conn.request_path == "/api/v1/signals/sampling"
      body = conn |> Req.Test.raw_body() |> Jason.decode!()
      assert body["app"] == "catalogo"
      assert body["rate"] == 0.25
      Req.Test.json(conn, %{"data" => %{"trace_sample_rate" => 0.25}})
    end)

    client = Client.new("https://panel.test", "tok")

    assert {:ok, %{"data" => %{"trace_sample_rate" => 0.25}}} =
             Client.update_signals_sampling(client, %{"app" => "catalogo", "rate" => 0.25})
  end

  test "list_servers returns the panel payload" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"data" => [%{"id" => 1, "name" => "srv"}]})
    end)

    client = Client.new("https://panel.test", "tok")

    assert {:ok, %{"data" => [%{"id" => 1, "name" => "srv"}]}} = Client.list_servers(client)
  end

  test "authenticated requests carry the bearer token" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert ["Bearer tok"] = Plug.Conn.get_req_header(conn, "authorization")
      Req.Test.json(conn, %{"data" => %{"user" => %{}, "tenant" => %{}, "role" => "owner"}})
    end)

    assert {:ok, _body} = Client.me(Client.new("https://panel.test", "tok"))
  end

  test "create_token posts credentials without an auth header" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert [] = Plug.Conn.get_req_header(conn, "authorization")
      body = Req.Test.raw_body(conn)
      assert Jason.decode!(body)["email"] == "a@b.test"
      Req.Test.json(conn, %{"token" => "cleat_abc"})
    end)

    assert {:ok, %{"token" => "cleat_abc"}} =
             Client.create_token("https://panel.test", "a@b.test", "pw")
  end

  test "API errors are humanized" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(401)
      |> Req.Test.json(%{"error" => "invalid_credentials"})
    end)

    assert {:error, message} = Client.create_token("https://panel.test", "a", "b")
    assert message =~ "Invalid credentials"
  end

  test "validation details are surfaced" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(422)
      |> Req.Test.json(%{
        "error" => "invalid_request",
        "details" => %{"slug" => ["has already been taken"]}
      })
    end)

    assert {:error, message} = Client.create_app(Client.new("https://panel.test", "t"), %{})
    assert message =~ "slug: has already been taken"
  end

  test "app_logs passes tail, since and grep as query params" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/v1/apps/lumina/logs"
      assert conn.query_string == "grep=error&since=1h&tail=50"
      Req.Test.json(conn, %{"data" => %{"lines" => []}})
    end)

    client = Client.new("https://panel.test", "tok")

    assert {:ok, %{"data" => %{"lines" => []}}} =
             Client.app_logs(client, "lumina", %{since: "1h", tail: 50, grep: "error"})
  end

  test "server_logs passes filters as query params" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/v1/servers/5/logs"
      assert conn.query_string == "tail=100"
      Req.Test.json(conn, %{"data" => %{"lines" => []}})
    end)

    client = Client.new("https://panel.test", "tok")

    assert {:ok, %{"data" => %{"lines" => []}}} = Client.server_logs(client, 5, %{tail: 100})
  end

  test "app_logs/2 still works without query params" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/apps/lumina/logs"
      assert conn.query_string == ""
      Req.Test.json(conn, %{"data" => %{"lines" => []}})
    end)

    client = Client.new("https://panel.test", "tok")

    assert {:ok, %{"data" => %{"lines" => []}}} = Client.app_logs(client, "lumina")
  end

  test "trailing slash in the panel URL is trimmed" do
    assert %Client{panel_url: "https://panel.test"} = Client.new("https://panel.test/")
  end

  test "surfaces the panel's message on an error response" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(422)
      |> Req.Test.json(%{
        "error" => "invalid_request",
        "message" => "invalid since (use 30m, 2h, 1d)"
      })
    end)

    client = Client.new("https://panel.test", "tok")

    assert {:error, message} = Client.server_logs(client, 5, %{since: "nope"})
    assert message =~ "Invalid request"
    assert message =~ "invalid since (use 30m, 2h, 1d)"
  end
end
