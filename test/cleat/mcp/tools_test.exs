defmodule Cleat.MCP.ToolsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Cleat.MCP.Tools

  @isolated_env ~w(CLEAT_CONFIG CLEAT_BASE_DOMAIN CLEAT_SITES_BASE_DOMAIN)

  setup do
    Application.put_env(:cleat_cli, :req_plug, {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:cleat_cli, :req_plug) end)

    path = Path.join(System.tmp_dir!(), "cleat_cfg_#{System.unique_integer([:positive])}.json")
    previous = Map.new(@isolated_env, &{&1, System.get_env(&1)})

    System.put_env("CLEAT_CONFIG", path)
    Enum.each(~w(CLEAT_BASE_DOMAIN CLEAT_SITES_BASE_DOMAIN), &System.delete_env/1)

    on_exit(fn ->
      Enum.each(previous, fn {key, value} -> restore_env(key, value) end)
      File.rm(path)
    end)

    :ok
  end

  test "lists every expected tool" do
    names = Tools.list() |> Enum.map(& &1["name"])

    assert names == [
             "whoami",
             "servers_list",
             "apps_list",
             "apps_show",
             "apps_create",
             "apps_update",
             "apps_logs",
             "env_list",
             "env_set",
             "env_unset",
             "deploy",
             "deploy_status",
             "deploy_logs",
             "cancel_deploy",
             "drop",
             "init_project"
           ]
  end

  test "every tool exposes a JSON schema object" do
    for tool <- Tools.list() do
      assert %{"type" => "object"} = tool["inputSchema"]
      assert is_binary(tool["description"])
    end
  end

  test "call/2 dispatches to the handler and returns a text result" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/me"
      Req.Test.json(conn, %{"data" => %{"email" => "me@example.com"}})
    end)

    assert {:ok, text} =
             Tools.call("whoami", %{"panel" => "https://panel.test", "token" => "tok"})

    assert is_binary(text)
    assert Jason.decode!(text)["email"] == "me@example.com"
  end

  test "call/2 reports an unknown tool" do
    assert {:error, message} = Tools.call("nope", %{})
    assert message =~ "unknown tool"
  end

  test "call/2 validates required arguments" do
    assert {:error, message} = Tools.call("apps_show", %{})
    assert message =~ "app"
  end

  test "call/2 rejects non-map arguments" do
    assert {:error, "invalid arguments"} = Tools.call("whoami", [])
  end

  test "call/2 converts handler exceptions into errors" do
    assert {:error, message} = Tools.call("whoami", %{"panel" => 123, "token" => "tok"})
    assert is_binary(message)
  end

  test "call/2 surfaces a client error from a non-2xx response" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(404)
      |> Req.Test.json(%{"error" => "not_found"})
    end)

    assert {:error, message} =
             Tools.call("apps_show", %{
               "app" => "x",
               "panel" => "https://panel.test",
               "token" => "tok"
             })

    assert message =~ "Not found"
  end

  test "apps_update with an empty update returns an actionable error" do
    assert {:error, message} = Tools.call("apps_update", %{"app" => "my-app"})
    assert message =~ "nothing to update"
  end

  test "init_project does not write to stdout" do
    dir =
      Path.join(System.tmp_dir!(), "cleat-mcp-init-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    original = File.cwd!()
    File.cd!(dir)

    on_exit(fn ->
      File.cd!(original)
      File.rm_rf(dir)
    end)

    output =
      capture_io(fn ->
        assert {:ok, text} = Tools.call("init_project", %{"overwrite" => true})
        assert Jason.decode!(text)["created"] == ".cleat_deploy/deploy.json"
      end)

    assert output == ""
  end

  test "apps_create posts the mapped body to /api/v1/apps" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/v1/apps"

      body = Jason.decode!(Req.Test.raw_body(conn))
      assert body["name"] == "landing"
      assert body["github_repo"] == "owner/site"
      assert body["host"] == "landing.example.com"
      assert body["server_id"] == "3"
      assert body["runtime"] == "static"
      assert body["branch"] == "main"
      assert body["port"] == 4000
      refute Map.has_key?(body, "slug")

      Req.Test.json(conn, %{"data" => %{"id" => 1, "slug" => "landing"}})
    end)

    assert {:ok, _text} =
             Tools.call("apps_create", %{
               "name" => "landing",
               "repo" => "owner/site",
               "host" => "landing.example.com",
               "server" => "3",
               "runtime" => "static",
               "branch" => "main",
               "port" => 4000,
               "panel" => "https://panel.test",
               "token" => "tok"
             })
  end

  test "env_set PUTs vars to the app env endpoint" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "PUT"
      assert conn.request_path == "/api/v1/apps/landing/env"
      assert Jason.decode!(Req.Test.raw_body(conn)) == %{"vars" => %{"FOO" => "bar"}}
      Req.Test.json(conn, %{"data" => %{"ok" => true}})
    end)

    assert {:ok, _text} =
             Tools.call("env_set", %{
               "app" => "landing",
               "vars" => %{"FOO" => "bar"},
               "panel" => "https://panel.test",
               "token" => "tok"
             })
  end

  test "env_unset DELETEs one key" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "DELETE"
      assert conn.request_path == "/api/v1/apps/landing/env/OLD_KEY"
      Req.Test.json(conn, %{"data" => %{"ok" => true}})
    end)

    assert {:ok, _text} =
             Tools.call("env_unset", %{
               "app" => "landing",
               "key" => "OLD_KEY",
               "panel" => "https://panel.test",
               "token" => "tok"
             })
  end

  test "deploy POSTs the git ref to the app deployments endpoint" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/v1/apps/landing/deployments"
      assert Jason.decode!(Req.Test.raw_body(conn)) == %{"git_ref" => "deploy-cleat"}
      Req.Test.json(conn, %{"data" => %{"id" => 42, "status" => "queued"}})
    end)

    assert {:ok, text} =
             Tools.call("deploy", %{
               "app" => "landing",
               "ref" => "deploy-cleat",
               "panel" => "https://panel.test",
               "token" => "tok"
             })

    assert Jason.decode!(text)["id"] == 42
  end

  test "deploy_logs GETs the deployment by id" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/v1/deployments/42"
      Req.Test.json(conn, %{"data" => %{"id" => 42, "log" => "Building"}})
    end)

    assert {:ok, text} =
             Tools.call("deploy_logs", %{
               "id" => 42,
               "panel" => "https://panel.test",
               "token" => "tok"
             })

    assert Jason.decode!(text)["log"] == "Building"
  end

  test "cancel_deploy POSTs to the app cancel endpoint" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/v1/apps/landing/cancel"
      Req.Test.json(conn, %{"data" => %{"status" => "cancelled"}})
    end)

    assert {:ok, _text} =
             Tools.call("cancel_deploy", %{
               "app" => "landing",
               "panel" => "https://panel.test",
               "token" => "tok"
             })
  end

  test "drop uploads a tarball to an existing app" do
    dir = temp_drop_dir()

    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/v1/apps/landing/drops"
      assert {"content-type", "application/gzip"} in conn.req_headers
      assert <<0x1F, 0x8B, _::binary>> = Req.Test.raw_body(conn)

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"data" => %{"id" => 7, "status" => "queued"}})
    end)

    assert {:ok, text} =
             Tools.call("drop", %{
               "path" => dir,
               "app" => "landing",
               "panel" => "https://panel.test",
               "token" => "tok"
             })

    assert Jason.decode!(text)["id"] == 7
  end

  test "drop registers a static app when only server and host are given" do
    dir = temp_drop_dir()
    slug = dir |> Path.basename() |> slugify()
    drops_path = "/api/v1/apps/#{slug}/drops"

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{"data" => []})

        {"POST", "/api/v1/apps"} ->
          body = Jason.decode!(Req.Test.raw_body(conn))
          assert body["runtime"] == "static"
          assert body["server_id"] == "3"
          assert body["host"] == "new.example.com"
          assert body["slug"] == slug

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 5, "slug" => slug}})

        {"POST", ^drops_path} ->
          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 8, "status" => "queued"}})
      end
    end)

    assert {:ok, text} =
             Tools.call("drop", %{
               "path" => dir,
               "server" => "3",
               "host" => "New.Example.COM",
               "panel" => "https://panel.test",
               "token" => "tok"
             })

    assert Jason.decode!(text)["id"] == 8
  end

  test "drop without app or server and host is an actionable error" do
    dir = temp_drop_dir()

    assert {:error, message} =
             Tools.call("drop", %{
               "path" => dir,
               "panel" => "https://panel.test",
               "token" => "tok"
             })

    assert message =~ "drop requires app, or server"
  end

  test "drop derives a sites host for a static path without host" do
    dir = Path.join(System.tmp_dir!(), "mcp-drop-static-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    on_exit(fn -> File.rm_rf(dir) end)

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{"data" => []})

        {"POST", "/api/v1/apps"} ->
          body = Jason.decode!(Req.Test.raw_body(conn))
          assert body["host"] == body["slug"] <> ".sites.example.com"
          assert body["runtime"] == "static"

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 80, "slug" => body["slug"]}})

        {"POST", "/api/v1/apps/" <> _} ->
          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 81, "status" => "queued"}})
      end
    end)

    assert {:ok, _text} =
             Tools.call("drop", %{
               "path" => dir,
               "server" => "5",
               "sites_base_domain" => "sites.example.com",
               "panel" => "https://panel.test",
               "token" => "tok"
             })
  end

  test "drop reuses an existing static app by slug" do
    dir = Path.join(System.tmp_dir!(), "mcp-drop-reuse-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    on_exit(fn -> File.rm_rf(dir) end)

    slug = Cleat.Static.site_slug(dir)

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{
            "data" => [
              %{
                "slug" => slug,
                "runtime" => "static",
                "host" => "#{slug}.sites.example.com"
              }
            ]
          })

        {"POST", "/api/v1/apps/" <> _} ->
          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 82, "status" => "queued"}})

        other ->
          flunk("unexpected request #{inspect(other)}")
      end
    end)

    assert {:ok, _text} =
             Tools.call("drop", %{
               "path" => dir,
               "server" => "5",
               "sites_base_domain" => "sites.example.com",
               "panel" => "https://panel.test",
               "token" => "tok"
             })
  end

  test "drop reuses an existing static app with no domain configured" do
    dir =
      Path.join(System.tmp_dir!(), "mcp-drop-nodomain-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    on_exit(fn -> File.rm_rf(dir) end)

    slug = Cleat.Static.site_slug(dir)

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{
            "data" => [
              %{"slug" => slug, "runtime" => "static", "host" => "#{slug}.sites.example.com"}
            ]
          })

        {"POST", "/api/v1/apps"} ->
          flunk("drop must reuse the existing app instead of registering one")

        {"POST", "/api/v1/apps/" <> _} ->
          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 83, "status" => "queued"}})

        other ->
          flunk("unexpected request #{inspect(other)}")
      end
    end)

    assert {:ok, text} =
             Tools.call("drop", %{
               "path" => dir,
               "server" => "5",
               "panel" => "https://panel.test",
               "token" => "tok"
             })

    assert Jason.decode!(text)["id"] == 83
  end

  test "drop errors when an explicit host differs from the existing static app host" do
    dir =
      Path.join(System.tmp_dir!(), "mcp-drop-hostclash-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    on_exit(fn -> File.rm_rf(dir) end)

    slug = Cleat.Static.site_slug(dir)

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{
            "data" => [
              %{"slug" => slug, "runtime" => "static", "host" => "existing.example.com"}
            ]
          })

        other ->
          flunk("unexpected request #{inspect(other)}")
      end
    end)

    assert {:error, message} =
             Tools.call("drop", %{
               "path" => dir,
               "server" => "5",
               "host" => "other.example.com",
               "panel" => "https://panel.test",
               "token" => "tok"
             })

    assert message =~ "existing.example.com"
    assert message =~ "already exists"
  end

  test "drop host clash falls back when the existing static app has no host" do
    dir =
      Path.join(System.tmp_dir!(), "mcp-drop-nohost-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    on_exit(fn -> File.rm_rf(dir) end)

    slug = Cleat.Static.site_slug(dir)

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{
            "data" => [%{"slug" => slug, "runtime" => "static", "host" => nil}]
          })

        other ->
          flunk("unexpected request #{inspect(other)}")
      end
    end)

    assert {:error, message} =
             Tools.call("drop", %{
               "path" => dir,
               "server" => "5",
               "host" => "other.example.com",
               "panel" => "https://panel.test",
               "token" => "tok"
             })

    assert message =~ "already exists"
    assert message =~ "unset host"
    refute message =~ "on ;"
  end

  test "drop errors when the slug exists with another runtime" do
    dir = temp_drop_dir()
    slug = Cleat.Static.site_slug(dir)

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{
            "data" => [%{"slug" => slug, "runtime" => "docker", "host" => "x.example.com"}]
          })

        other ->
          flunk("unexpected request #{inspect(other)}")
      end
    end)

    assert {:error, message} =
             Tools.call("drop", %{
               "path" => dir,
               "server" => "5",
               "host" => "x.example.com",
               "panel" => "https://panel.test",
               "token" => "tok"
             })

    assert message =~ "docker"
  end

  test "drop does not write to stdout" do
    dir = temp_drop_dir()

    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/apps/landing/drops"

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"data" => %{"id" => 9, "status" => "queued"}})
    end)

    output =
      capture_io(fn ->
        assert {:ok, text} =
                 Tools.call("drop", %{
                   "path" => dir,
                   "app" => "landing",
                   "panel" => "https://panel.test",
                   "token" => "tok"
                 })

        assert Jason.decode!(text)["id"] == 9
      end)

    assert output == ""
  end

  test "drop errors when a non-static path has no host" do
    dir = Path.join(System.tmp_dir!(), "mcp-drop-build-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "package.json"), ~s({"name":"x"}))
    on_exit(fn -> File.rm_rf(dir) end)

    Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"data" => []}) end)

    assert {:error, message} = Tools.call("drop", %{"path" => dir, "server" => "5"})
    assert message =~ "host"
  end

  test "call/2 rejects token '-' (stdin) over MCP" do
    assert {:error, message} =
             Tools.call("whoami", %{"panel" => "https://panel.test", "token" => "-"})

    assert message =~ "stdin"
  end

  defp temp_drop_dir do
    dir = Path.join(System.tmp_dir!(), "cleat-mcp-drop-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "index.html"), "<html>hi</html>")
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
