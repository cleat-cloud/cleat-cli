defmodule Cleat.MCP.Tools.Observability do
  @moduledoc false

  alias Cleat.{Client, Commands}
  alias Cleat.MCP.Tools.{Schema, Support}

  @doc false
  def tools do
    [
      %{
        "name" => "logs_search",
        "description" =>
          "Search collected log events by app, server, unit, text, severity, release, environment and time window. Set group=true for clustered errors.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "app" => Schema.app(),
            "server" => %{"type" => "string", "description" => "Server id"},
            "unit" => %{"type" => "string"},
            "q" => %{"type" => "string", "description" => "Case-insensitive substring"},
            "severity" => %{
              "type" => "string",
              "description" => "Exact level: emerg alert crit err warning notice info debug"
            },
            "min_severity" => %{
              "type" => "string",
              "description" => "Include this level and above"
            },
            "release" => %{"type" => "string", "description" => "Deployment id or git sha prefix"},
            "environment" => %{"type" => "string", "description" => "App branch / environment"},
            "group" => %{"type" => "boolean", "description" => "Cluster similar errors"},
            "since" => %{"type" => "string", "description" => "30m, 2h, 1d or ISO time"},
            "until" => %{"type" => "string", "description" => "ISO time"},
            "limit" => %{"type" => "integer"},
            "panel" => Schema.panel(),
            "token" => Schema.token()
          }
        },
        "handler" => fn args ->
          params =
            %{
              "app" => args["app"],
              "server" => args["server"],
              "unit" => args["unit"],
              "q" => args["q"],
              "severity" => args["severity"],
              "min_severity" => args["min_severity"],
              "release" => args["release"],
              "environment" => args["environment"],
              "since" => args["since"],
              "until" => args["until"],
              "limit" => args["limit"]
            }
            |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
            |> Map.new()

          Support.with_client(args, fn client ->
            result =
              if args["group"] do
                Client.search_log_groups(client, params)
              else
                Client.search_logs(client, params)
              end

            with {:ok, body} <- result, do: {:ok, Support.data_text(body)}
          end)
        end
      },
      %{
        "name" => "signals_health",
        "description" =>
          "Overview of application health from collected logs (degraded/down, reasons, preceding release). Optional app filter.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "app" => Schema.app(),
            "panel" => Schema.panel(),
            "token" => Schema.token()
          }
        },
        "handler" => fn args ->
          params = Support.compact_params(%{"app" => args["app"]})

          Support.with_client(args, fn client ->
            with {:ok, body} <- Client.signals_health(client, params),
                 do: {:ok, Support.data_text(body)}
          end)
        end
      },
      %{
        "name" => "signals_metrics",
        "description" =>
          "RED metrics, host snapshot and deploy markers for one app. range is 1h, 6h, 24h or 1d.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "app" => Schema.app(),
            "range" => %{"type" => "string", "description" => "1h, 6h, 24h or 1d"},
            "panel" => Schema.panel(),
            "token" => Schema.token()
          },
          "required" => ["app"]
        },
        "handler" => fn args ->
          params = Support.compact_params(%{"app" => args["app"], "range" => args["range"]})

          Support.with_client(args, fn client ->
            with {:ok, body} <- Client.signals_metrics(client, params),
                 do: {:ok, Support.data_text(body)}
          end)
        end
      },
      %{
        "name" => "signals_pages",
        "description" =>
          "Most requested HTTP paths from Caddy access logs for one app, plus visited pageviews when analytics inject is on. range is 1h, 6h, 24h or 1d.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "app" => Schema.app(),
            "range" => %{"type" => "string", "description" => "1h, 6h, 24h or 1d"},
            "panel" => Schema.panel(),
            "token" => Schema.token()
          },
          "required" => ["app"]
        },
        "handler" => fn args ->
          params = Support.compact_params(%{"app" => args["app"], "range" => args["range"]})

          Support.with_client(args, fn client ->
            with {:ok, body} <- Client.signals_pages(client, params),
                 do: {:ok, Support.data_text(body)}
          end)
        end
      },
      %{
        "name" => "signals_alerts",
        "description" => "List open default alerts. Pass id to ack a firing alert.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => "string", "description" => "Alert id to ack"},
            "panel" => Schema.panel(),
            "token" => Schema.token()
          }
        },
        "handler" => fn args ->
          Support.with_client(args, fn client ->
            result =
              case args["id"] do
                id when is_binary(id) and id != "" -> Client.ack_signal_alert(client, id)
                id when is_integer(id) -> Client.ack_signal_alert(client, id)
                _ -> Client.signals_alerts(client)
              end

            with {:ok, body} <- result, do: {:ok, Support.data_text(body)}
          end)
        end
      },
      %{
        "name" => "signals_traces",
        "description" =>
          "List traces for an app, or fetch waterfall, service map and correlated logs when trace_id is set.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "app" => Schema.app(),
            "trace_id" => %{"type" => "string", "description" => "Open one trace waterfall"},
            "service" => %{"type" => "string", "description" => "Filter traces by service name"},
            "panel" => Schema.panel(),
            "token" => Schema.token()
          },
          "required" => ["app"]
        },
        "handler" => fn args ->
          params =
            Support.compact_params(%{
              "app" => args["app"],
              "trace_id" => args["trace_id"],
              "service" => args["service"]
            })

          Support.with_client(args, fn client ->
            with {:ok, body} <- Client.signals_traces(client, params),
                 do: {:ok, Support.data_text(body)}
          end)
        end
      },
      %{
        "name" => "signals_set_sampling",
        "description" =>
          "Set the fraction of traces stored for an app (0 disables ingest, 1 stores all).",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "app" => Schema.app(),
            "rate" => %{
              "type" => "number",
              "description" => "Sample rate between 0 and 1"
            },
            "panel" => Schema.panel(),
            "token" => Schema.token()
          },
          "required" => ["app", "rate"]
        },
        "handler" => fn args ->
          Support.with_client(args, fn client ->
            with {:ok, body} <-
                   Client.update_signals_sampling(client, %{
                     "app" => args["app"],
                     "rate" => args["rate"]
                   }) do
              {:ok, Support.data_text(body)}
            end
          end)
        end
      },
      %{
        "name" => "analytics_requested",
        "description" =>
          "Most requested apps in the last 24h on the active server, from Caddy's access log (HTTP hits, not pageviews).",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{"panel" => Schema.panel(), "token" => Schema.token()}
        },
        "handler" => fn args ->
          Support.with_client(args, fn client ->
            with {:ok, body} <- Client.analytics_requested(client),
                 do: {:ok, Support.data_text(body)}
          end)
        end
      },
      %{
        "name" => "analytics_visited",
        "description" =>
          "Most visited apps in the last 24h by JS pageviews on the active server (inject-on only). stale=true means the sidecar did not answer.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{"panel" => Schema.panel(), "token" => Schema.token()}
        },
        "handler" => fn args ->
          Support.with_client(args, fn client ->
            with {:ok, body} <- Client.analytics_visited(client) do
              {:ok,
               Support.json(%{
                 "data" => Commands.data(body),
                 "stale" => body["stale"] == true
               })}
            end
          end)
        end
      },
      %{
        "name" => "analytics_summary",
        "description" =>
          "Pageview summary for one app: pageviews, uniques, series, top paths, referrers and UTM. range is 24h, 7d or 90d; stale=true means the sidecar did not answer.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "app" => Schema.app(),
            "range" => %{"type" => "string", "description" => "24h, 7d or 90d"},
            "panel" => Schema.panel(),
            "token" => Schema.token()
          },
          "required" => ["app"]
        },
        "handler" => fn args ->
          params = Support.compact_params(%{"range" => args["range"]})

          Support.with_client(args, fn client ->
            with {:ok, body} <- Client.analytics_summary(client, args["app"], params) do
              {:ok, Support.data_text(body)}
            end
          end)
        end
      }
    ]
  end
end
