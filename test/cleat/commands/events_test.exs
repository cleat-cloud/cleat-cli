defmodule Cleat.Commands.EventsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Cleat.Commands.Events

  @conn %{panel: "https://panel.test", token: "tok"}

  setup do
    Application.put_env(:cleat_cli, :req_plug, {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:cleat_cli, :req_plug) end)
    :ok
  end

  test "prints collected events as a table" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/v1/logs"

      Req.Test.json(conn, %{"data" => [event("err", "boom happened")]})
    end)

    output = capture_io(fn -> assert :ok = Events.run([], @conn) end)
    assert output =~ "boom happened"
    assert output =~ "err"
    assert output =~ "phx-app.service"
  end

  test "passes the positional app and the search filters" do
    Req.Test.stub(__MODULE__, fn conn ->
      params = URI.decode_query(conn.query_string)
      assert params["app"] == "my-app"
      assert params["min_severity"] == "warning"
      assert params["q"] == "timeout"
      assert params["limit"] == "50"

      Req.Test.json(conn, %{"data" => []})
    end)

    assert :ok =
             Events.run(
               ["my-app"],
               @conn
               |> Map.put(:min_severity, "warning")
               |> Map.put(:query, "timeout")
               |> Map.put(:limit, 50)
             )
  end

  test "reports when nothing matches" do
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"data" => []}) end)

    output = capture_io(fn -> assert :ok = Events.run([], @conn) end)
    assert output =~ "No log events matched"
  end

  test "rejects an unknown severity" do
    assert {:error, message} = Events.run([], Map.put(@conn, :severity, "nope"))
    assert message =~ "invalid --severity"
  end

  test "json mode prints the raw events" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"data" => [event("info", "hi")]})
    end)

    output = capture_io(fn -> assert :ok = Events.run([], Map.put(@conn, :json, true)) end)
    assert output =~ ~s("message": "hi")
  end

  defp event(severity, message) do
    %{
      "id" => 1,
      "app_id" => 7,
      "server_id" => 5,
      "deployment_id" => nil,
      "unit" => "phx-app.service",
      "source" => "app",
      "severity" => severity,
      "message" => message,
      "occurred_at" => "2026-09-28T12:00:00Z"
    }
  end
end
