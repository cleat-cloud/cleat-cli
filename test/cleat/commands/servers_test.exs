defmodule Cleat.Commands.ServersTest do
  use ExUnit.Case, async: false

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
end
