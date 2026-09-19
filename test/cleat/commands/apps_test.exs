defmodule Cleat.Commands.AppsTest do
  use ExUnit.Case, async: false

  alias Cleat.Commands.Apps

  @conn %{panel: "https://panel.test", token: "tok"}

  setup do
    Application.put_env(:cleat_cli, :req_plug, {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:cleat_cli, :req_plug) end)
    :ok
  end

  test "updates branch and auto-deploy" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "PATCH"
      assert conn.request_path == "/api/v1/apps/my-app"

      assert Jason.decode!(Req.Test.raw_body(conn)) ==
               %{"branch" => "develop", "auto_deploy" => false}

      Req.Test.json(conn, %{
        "data" => %{"slug" => "my-app", "branch" => "develop", "auto_deploy" => false}
      })
    end)

    assert :ok =
             Apps.run(
               ["update", "my-app"],
               Map.put(@conn, :branch, "develop") |> Map.put(:auto_deploy, false)
             )
  end

  test "requires at least one field to update" do
    assert {:error, message} = Apps.run(["update", "my-app"], @conn)
    assert message =~ "nothing to update"
  end

  test "create rejects a request missing required options" do
    assert {:error, message} = Apps.run(["create"], @conn)
    assert message =~ "--repo"
    assert message =~ "--server"
  end
end
