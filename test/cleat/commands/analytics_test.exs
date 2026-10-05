defmodule Cleat.Commands.AnalyticsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Cleat.Commands.Analytics

  @conn %{panel: "https://panel.test", token: "tok"}

  setup do
    Application.put_env(:cleat_cli, :req_plug, {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:cleat_cli, :req_plug) end)
    :ok
  end

  test "requested prints the 24h ranking with host" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/analytics/requested"

      Req.Test.json(conn, %{
        "data" => [
          %{
            "app_id" => 55,
            "slug" => "nfe-facil",
            "name" => "NFe Fácil",
            "host" => "nfe.gestaobem.com",
            "requests" => 40
          }
        ]
      })
    end)

    output = capture_io(fn -> assert :ok = Analytics.run(["requested"], @conn) end)

    assert output =~ "nfe-facil"
    assert output =~ "nfe.gestaobem.com"
    assert output =~ "40"
  end

  test "requested with --json prints the rows" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"data" => [%{"slug" => "nfe-facil", "requests" => 1}]})
    end)

    output =
      capture_io(fn -> assert :ok = Analytics.run(["requested"], Map.put(@conn, :json, true)) end)

    assert Jason.decode!(output) == [%{"slug" => "nfe-facil", "requests" => 1}]
  end

  test "visited prints the ranking and notes staleness" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/analytics/visited"

      Req.Test.json(conn, %{
        "data" => [
          %{"slug" => "fagulha-app", "host" => "fagulha.apps.gestaobem.com", "pageviews" => 12}
        ],
        "stale" => true
      })
    end)

    output = capture_io(fn -> assert :ok = Analytics.run(["visited"], @conn) end)

    assert output =~ "stale"
    assert output =~ "fagulha-app"
    assert output =~ "12"
  end

  test "visited tells when there is nothing" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"data" => [], "stale" => false})
    end)

    output = capture_io(fn -> assert :ok = Analytics.run(["visited"], @conn) end)
    assert output =~ "No pageviews"
  end

  test "show forwards the range and prints the summary" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/apps/fagulha-app/analytics"
      assert URI.decode_query(conn.query_string)["range"] == "7d"

      Req.Test.json(conn, %{
        "data" => %{
          "app_id" => 72,
          "slug" => "fagulha-app",
          "range" => "7d",
          "pageviews" => 42,
          "uniques" => 7,
          "series" => [],
          "paths" => [%{"path" => "/", "pageviews" => 30}],
          "referrers" => [%{"referrer" => "google.com", "pageviews" => 4}],
          "utm" => [
            %{"source" => "news", "medium" => "email", "campaign" => "launch", "pageviews" => 2}
          ],
          "stale" => false
        }
      })
    end)

    output =
      capture_io(fn ->
        assert :ok = Analytics.run(["show", "fagulha-app"], Map.put(@conn, :range, "7d"))
      end)

    assert output =~ "fagulha-app"
    assert output =~ "42"
    assert output =~ "google.com"
    assert output =~ "news/email/launch"
  end

  test "show flags a stale summary" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{
          "slug" => "fagulha-app",
          "range" => "24h",
          "pageviews" => 0,
          "uniques" => 0,
          "series" => [],
          "paths" => [],
          "referrers" => [],
          "utm" => [],
          "stale" => true
        }
      })
    end)

    output = capture_io(fn -> assert :ok = Analytics.run(["show", "fagulha-app"], @conn) end)
    assert output =~ "STALE"
  end

  test "show without an app returns usage" do
    assert {:error, message} = Analytics.run(["show"], @conn)
    assert message =~ "usage"
  end

  test "an unknown subcommand returns usage" do
    assert {:error, message} = Analytics.run(["nope"], @conn)
    assert message =~ "usage"
  end
end
