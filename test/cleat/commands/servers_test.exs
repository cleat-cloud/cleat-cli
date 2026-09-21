defmodule Cleat.Commands.ServersTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Cleat.Commands.Servers

  @conn %{panel: "https://panel.test", token: "tok"}

  setup do
    Application.put_env(:cleat_cli, :req_plug, {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:cleat_cli, :req_plug) end)
    :ok
  end

  test "creates a server, reading the SSH key from a file" do
    key = Path.join(System.tmp_dir!(), "cleat-key-#{System.unique_integer([:positive])}.pem")
    File.write!(key, "PRIVATE KEY")
    on_exit(fn -> File.rm(key) end)

    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/v1/servers"

      body = Jason.decode!(Req.Test.raw_body(conn))
      assert body["name"] == "box"
      assert body["host_ip"] == "10.0.0.5"
      assert body["ssh_private_key"] == "PRIVATE KEY"

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"data" => %{"id" => 3, "name" => "box", "host_ip" => "10.0.0.5"}})
    end)

    assert :ok =
             Servers.run(
               ["create"],
               @conn
               |> Map.put(:name, "box")
               |> Map.put(:ip, "10.0.0.5")
               |> Map.put(:ssh_key_file, key)
             )
  end

  test "deletes a server with --yes" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "DELETE"
      assert conn.request_path == "/api/v1/servers/3"
      Plug.Conn.send_resp(conn, 204, "")
    end)

    assert :ok = Servers.run(["delete", "3"], Map.put(@conn, :yes, true))
  end

  test "refuses to delete without --yes" do
    assert {:error, message} = Servers.run(["delete", "3"], @conn)
    assert message =~ "--yes"
  end

  test "stops a server" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/v1/servers/3/stop"

      Req.Test.json(conn, %{"data" => %{"id" => 3, "instance_status" => "stopped"}})
    end)

    assert :ok = Servers.run(["stop", "3"], @conn)
  end

  test "starts a server" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/v1/servers/3/start"

      Req.Test.json(conn, %{"data" => %{"id" => 3, "instance_status" => "running"}})
    end)

    assert :ok = Servers.run(["start", "3"], @conn)
  end

  test "provisions a VM" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/v1/servers/provision"

      body = Jason.decode!(Req.Test.raw_body(conn))
      assert body["name"] == "box"
      assert body["bundle_id"] == "cx33"

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"data" => %{"id" => 5, "name" => "box", "host_ip" => "203.0.113.7"}})
    end)

    assert :ok =
             Servers.run(
               ["provision"],
               @conn |> Map.put(:name, "box") |> Map.put(:bundle, "cx33")
             )
  end

  test "resizes a server" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/v1/servers/3/resize"
      assert Jason.decode!(Req.Test.raw_body(conn)) == %{"bundle_id" => "cx43"}

      Req.Test.json(conn, %{"data" => %{"id" => 3, "bundle_id" => "cx43"}})
    end)

    assert :ok = Servers.run(["resize", "3"], Map.put(@conn, :bundle, "cx43"))
  end

  test "lists resize options when no bundle is given" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/v1/servers/3/resize-options"

      Req.Test.json(conn, %{"data" => [%{"bundle_id" => "cx43", "bundle_name" => "CX43"}]})
    end)

    output = capture_io(fn -> assert :ok = Servers.run(["resize", "3"], @conn) end)
    assert output =~ "cx43"
  end

  test "syncs server specs" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/v1/servers/3/sync"

      Req.Test.json(conn, %{
        "data" => %{"id" => 3, "bundle_name" => "Nano", "instance_status" => "running"}
      })
    end)

    assert :ok = Servers.run(["sync", "3"], @conn)
  end

  test "prints server logs" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/v1/servers/5/logs"

      Req.Test.json(conn, %{"data" => %{"lines" => ["host line one", "host line two"]}})
    end)

    output = capture_io(fn -> assert :ok = Servers.run(["logs", "5"], @conn) end)
    assert output =~ "host line one"
    assert output =~ "host line two"
  end

  test "passes --unit to the server logs endpoint" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/v1/servers/5/logs"
      assert URI.decode_query(conn.query_string) == %{"unit" => "caddy"}

      Req.Test.json(conn, %{"data" => %{"lines" => []}})
    end)

    assert :ok = Servers.run(["logs", "5"], Map.put(@conn, :unit, "caddy"))
  end

  test "passes log filters to the server logs endpoint" do
    Req.Test.stub(__MODULE__, fn conn ->
      params = URI.decode_query(conn.query_string)
      assert params["tail"] == "50"
      assert params["since"] == "1h"
      assert params["grep"] == "error"

      Req.Test.json(conn, %{"data" => %{"lines" => []}})
    end)

    assert :ok =
             Servers.run(
               ["logs", "5"],
               @conn
               |> Map.put(:tail, 50)
               |> Map.put(:since, "1h")
               |> Map.put(:grep, "error")
             )
  end
end
