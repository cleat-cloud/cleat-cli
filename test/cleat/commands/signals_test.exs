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

  test "traces lists traces for an app" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/v1/signals/traces"
      params = URI.decode_query(conn.query_string)
      assert params["app"] == "catalogo"
      refute Map.has_key?(params, "trace_id")

      Req.Test.json(conn, %{
        "data" => [
          %{
            "trace_id" => "5b8aa5a2d2c872e8321cf37308d69df2",
            "root_name" => "GET /checkout",
            "services" => ["shop", "payment"],
            "started_at" => "2026-10-01T21:00:00Z",
            "duration_ms" => 42,
            "span_count" => 2,
            "error" => false
          }
        ]
      })
    end)

    output = capture_io(fn -> assert :ok = Signals.run(["traces", "catalogo"], @conn) end)
    assert output =~ "5b8aa5a2d2c872e8321cf37308d69df2"
    assert output =~ "GET /checkout"
    assert output =~ "shop"
  end

  test "traces forwards --service and --trace-id" do
    Req.Test.stub(__MODULE__, fn conn ->
      params = URI.decode_query(conn.query_string)
      assert params["app"] == "catalogo"
      assert params["service"] == "payment"
      assert params["trace_id"] == "5b8aa5a2d2c872e8321cf37308d69df2"

      Req.Test.json(conn, %{
        "data" => %{
          "trace" => %{
            "trace_id" => "5b8aa5a2d2c872e8321cf37308d69df2",
            "root_name" => "GET /checkout",
            "services" => ["shop", "payment"],
            "duration_ms" => 42,
            "span_count" => 2,
            "error" => false
          },
          "spans" => [
            %{
              "span_id" => "051581bf3cb55c13",
              "parent_span_id" => nil,
              "name" => "GET /checkout",
              "service_name" => "shop",
              "duration_ms" => 42,
              "depth" => 0,
              "status_code" => "ok"
            },
            %{
              "span_id" => "5fb8a98c0bec6479",
              "parent_span_id" => "051581bf3cb55c13",
              "name" => "charge",
              "service_name" => "payment",
              "duration_ms" => 12,
              "depth" => 1,
              "status_code" => "ok"
            }
          ],
          "service_map" => %{
            "nodes" => ["shop", "payment"],
            "edges" => [%{"from" => "shop", "to" => "payment", "count" => 1}]
          },
          "logs" => [%{"id" => 9, "message" => "trace 5b8aa5a2d2c872e8321cf37308d69df2"}]
        }
      })
    end)

    output =
      capture_io(fn ->
        assert :ok =
                 Signals.run(
                   ["traces", "catalogo"],
                   Map.merge(@conn, %{
                     service: "payment",
                     trace_id: "5b8aa5a2d2c872e8321cf37308d69df2"
                   })
                 )
      end)

    assert output =~ "GET /checkout"
    assert output =~ "charge"
    assert output =~ "shop"
    assert output =~ "payment"
    assert output =~ "5b8aa5a2d2c872e8321cf37308d69df2"
  end

  test "traces without an app returns usage" do
    assert {:error, message} = Signals.run(["traces"], @conn)
    assert message =~ "usage"
  end

  test "sampling reads the current rate" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/v1/signals/sampling"
      assert URI.decode_query(conn.query_string)["app"] == "catalogo"

      Req.Test.json(conn, %{
        "data" => %{"app_id" => 6, "slug" => "catalogo", "trace_sample_rate" => 0.0}
      })
    end)

    output = capture_io(fn -> assert :ok = Signals.run(["sampling", "catalogo"], @conn) end)
    assert output =~ "catalogo"
    assert output =~ "0.0" or output =~ "0"
  end

  test "sampling --rate patches the panel" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "PATCH"
      assert conn.request_path == "/api/v1/signals/sampling"
      body = conn |> Req.Test.raw_body() |> Jason.decode!()
      assert body["app"] == "catalogo"
      assert body["rate"] == 0.5

      Req.Test.json(conn, %{
        "data" => %{"app_id" => 6, "slug" => "catalogo", "trace_sample_rate" => 0.5}
      })
    end)

    output =
      capture_io(fn ->
        assert :ok = Signals.run(["sampling", "catalogo"], Map.put(@conn, :rate, 0.5))
      end)

    assert output =~ "0.5"
  end

  test "sampling without an app returns usage" do
    assert {:error, message} = Signals.run(["sampling"], @conn)
    assert message =~ "usage"
  end

  test "unknown subcommand returns usage" do
    assert {:error, message} = Signals.run(["nope"], @conn)
    assert message =~ "usage"
  end
end
