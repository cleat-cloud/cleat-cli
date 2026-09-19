defmodule Cleat.Commands.DeployTest do
  use ExUnit.Case, async: false

  alias Cleat.Commands.Deploy

  setup do
    Application.put_env(:cleat_cli, :req_plug, {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:cleat_cli, :req_plug) end)
    :ok
  end

  test "triggers a deploy and reports success" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert ["Bearer tok"] = Plug.Conn.get_req_header(conn, "authorization")
      assert conn.request_path == "/api/v1/apps/my-app/deployments"

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"data" => %{"id" => 7, "status" => "queued"}})
    end)

    assert :ok = Deploy.run("my-app", %{panel: "https://panel.test", token: "tok"})
  end

  test "surfaces API errors" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(404)
      |> Req.Test.json(%{"error" => "not_found"})
    end)

    assert {:error, message} = Deploy.run("missing", %{panel: "https://panel.test", token: "tok"})
    assert message =~ "Not found"
  end
end
