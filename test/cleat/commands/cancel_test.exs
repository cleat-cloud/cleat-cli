defmodule Cleat.Commands.CancelTest do
  use ExUnit.Case, async: false

  alias Cleat.Commands.Cancel

  @conn %{panel: "https://panel.test", token: "tok"}

  setup do
    Application.put_env(:cleat_cli, :req_plug, {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:cleat_cli, :req_plug) end)
    :ok
  end

  test "cancels the active deploy" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/v1/apps/my-app/cancel"
      Req.Test.json(conn, %{"data" => %{"id" => 5, "status" => "failed"}})
    end)

    assert :ok = Cancel.run("my-app", @conn)
  end

  test "surfaces the no-active-deployment conflict" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(409)
      |> Req.Test.json(%{"error" => "no_active_deployment"})
    end)

    assert {:error, message} = Cancel.run("my-app", @conn)
    assert message =~ "No active deployment"
  end
end
