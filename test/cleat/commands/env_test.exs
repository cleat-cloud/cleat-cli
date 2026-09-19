defmodule Cleat.Commands.EnvTest do
  use ExUnit.Case, async: false

  alias Cleat.Commands.Env

  @conn %{panel: "https://panel.test", token: "tok"}

  setup do
    Application.put_env(:cleat_cli, :req_plug, {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:cleat_cli, :req_plug) end)
    :ok
  end

  test "sets several variables in one request" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "PUT"
      assert conn.request_path == "/api/v1/apps/my-app/env"
      assert Jason.decode!(Req.Test.raw_body(conn)) == %{"vars" => %{"FOO" => "1", "BAR" => "2"}}
      Req.Test.json(conn, %{"data" => []})
    end)

    assert :ok = Env.run(["set", "my-app", "FOO=1", "BAR=2"], @conn)
  end

  test "rejects a pair without an equals sign" do
    assert {:error, message} = Env.run(["set", "my-app", "NOPE"], @conn)
    assert message =~ "KEY=VALUE"
  end

  test "unsets a key" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "DELETE"
      assert conn.request_path == "/api/v1/apps/my-app/env/OLD_KEY"
      Plug.Conn.send_resp(conn, 204, "")
    end)

    assert :ok = Env.run(["unset", "my-app", "OLD_KEY"], @conn)
  end

  test "lists variables and requests reveal when asked" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/apps/my-app/env"
      assert conn.query_string == "reveal=true"
      Req.Test.json(conn, %{"data" => [%{"key" => "FOO", "value" => "1", "sensitive" => false}]})
    end)

    assert :ok = Env.run(["list", "my-app"], Map.put(@conn, :reveal, true))
  end
end
