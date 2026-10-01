defmodule Cleat.Commands.SignalsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Cleat.Commands.Signals

  @conn %{panel: "https://panel.test", token: "tok"}

  setup do
    Application.put_env(:cleat_cli, :req_plug, {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:cleat_cli, :req_plug) end)
    :ok
  end

  test "health prints degraded apps and the preceding release" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/v1/signals/health"

      Req.Test.json(conn, %{
        "data" => [
          %{
            "app_id" => 6,
            "slug" => "catalogo",
            "name" => "Catálogo",
            "status" => "degraded",
            "reasons" => ["error_rate"],
            "error_count" => 6,
            "previous_error_count" => 1,
            "preceding_release" => %{"id" => 12, "git_sha" => "bbb2222"}
          }
        ]
      })
    end)

    output = capture_io(fn -> assert :ok = Signals.run(["health"], @conn) end)
    assert output =~ "catalogo"
    assert output =~ "degraded"
    assert output =~ "error_rate"
    assert output =~ "bbb2222"
  end

  test "health passes an optional app filter" do
    Req.Test.stub(__MODULE__, fn conn ->
      params = URI.decode_query(conn.query_string)
      assert params["app"] == "catalogo"
      Req.Test.json(conn, %{"data" => []})
    end)

    capture_io(fn -> assert :ok = Signals.run(["health", "catalogo"], @conn) end)
  end

  test "metrics requires an app and forwards --range" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/signals/metrics"
      params = URI.decode_query(conn.query_string)
      assert params["app"] == "catalogo"
      assert params["range"] == "6h"

      Req.Test.json(conn, %{
        "data" => %{
          "app_id" => 6,
          "slug" => "catalogo",
          "range" => "6h",
          "red" => %{"errors" => 3, "logs" => 4, "error_rate" => 0.75, "latency_ms" => nil},
          "host" => %{"cpu" => nil, "memory" => nil, "disk" => nil, "restarts" => 0},
          "series" => [],
          "deploy_markers" => [%{"git_sha" => "cafebabe"}]
        }
      })
    end)

    output =
      capture_io(fn ->
        assert :ok = Signals.run(["metrics", "catalogo"], Map.put(@conn, :range, "6h"))
      end)

    assert output =~ "catalogo"
    assert output =~ "3"
    assert output =~ "cafebabe"
  end

  test "metrics without an app returns usage" do
    assert {:error, message} = Signals.run(["metrics"], @conn)
    assert message =~ "usage"
  end

  test "alerts lists firing rows" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/v1/signals/alerts"

      Req.Test.json(conn, %{
        "data" => [
          %{
            "id" => 9,
            "app_id" => 6,
            "slug" => "catalogo",
            "rule" => "error_rate",
            "status" => "firing",
            "message" => "Taxa de erro subiu em catalogo",
            "channel" => "in_app"
          }
        ]
      })
    end)

    output = capture_io(fn -> assert :ok = Signals.run(["alerts"], @conn) end)
    assert output =~ "catalogo"
    assert output =~ "error_rate"
    assert output =~ "Taxa de erro subiu em catalogo"
  end

  test "alerts ack posts to the panel" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/v1/signals/alerts/9/ack"

      Req.Test.json(conn, %{
        "data" => %{"id" => 9, "status" => "acked", "slug" => "catalogo", "rule" => "error_rate"}
      })
    end)

    output = capture_io(fn -> assert :ok = Signals.run(["alerts", "ack", "9"], @conn) end)
    assert output =~ "acked" or output =~ "9"
  end

  test "json mode prints the raw health payload" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"data" => [%{"slug" => "catalogo", "status" => "healthy"}]})
    end)

    output =
      capture_io(fn ->
        assert :ok = Signals.run(["health"], Map.put(@conn, :json, true))
      end)

    assert output =~ ~s("slug": "catalogo")
  end

  test "unknown subcommand returns usage" do
    assert {:error, message} = Signals.run(["nope"], @conn)
    assert message =~ "usage"
  end
end
