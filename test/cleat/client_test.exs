defmodule Cleat.ClientTest do
  use ExUnit.Case, async: false

  alias Cleat.Client

  setup do
    Application.put_env(:cleat_cli, :req_plug, {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:cleat_cli, :req_plug) end)
    :ok
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
end
