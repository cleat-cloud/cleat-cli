defmodule Cleat.Commands.DropTest do
  use ExUnit.Case, async: false

  alias Cleat.Commands.Drop

  @conn %{panel: "https://panel.test", token: "tok"}

  @isolated_env ~w(CLEAT_CONFIG CLEAT_BASE_DOMAIN CLEAT_SITES_BASE_DOMAIN)

  setup do
    dir = Path.join(System.tmp_dir!(), "cleat_drop_cmd_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "index.html"), "<html>hi</html>")
    File.write!(Path.join(dir, "style.css"), "body{}")

    on_exit(fn -> File.rm_rf(dir) end)

    Application.put_env(:cleat_cli, :req_plug, {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:cleat_cli, :req_plug) end)

    # Isolate from the developer's real config file and domain env vars.
    path = Path.join(System.tmp_dir!(), "cleat_cfg_#{System.unique_integer([:positive])}.json")
    previous = Map.new(@isolated_env, &{&1, System.get_env(&1)})

    System.put_env("CLEAT_CONFIG", path)
    Enum.each(~w(CLEAT_BASE_DOMAIN CLEAT_SITES_BASE_DOMAIN), &System.delete_env/1)

    on_exit(fn ->
      Enum.each(previous, fn {key, value} -> restore_env(key, value) end)
      File.rm(path)
    end)

    {:ok, dir: dir}
  end

  test "uploads a gzipped tarball to an existing app", %{dir: dir} do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/v1/apps/landing/drops"
      assert {"content-type", "application/gzip"} in conn.req_headers

      body = Req.Test.raw_body(conn)
      assert <<0x1F, 0x8B, _::binary>> = body

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"data" => %{"id" => 42, "status" => "queued"}})
    end)

    assert :ok = Drop.run([dir], Map.put(@conn, :app, "landing"))
  end

  test "auto-creates the static app before dropping", %{dir: dir} do
    slug = Path.basename(dir)
    drops_path = "/api/v1/apps/#{slug}/drops"

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{"data" => []})

        {"POST", "/api/v1/apps"} ->
          body = Jason.decode!(Req.Test.raw_body(conn))
          assert body["runtime"] == "static"
          refute Map.has_key?(body, "github_repo")
          assert body["host"] == "landing.example.com"

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 7, "slug" => slug}})

        {"POST", ^drops_path} ->
          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 8, "status" => "queued"}})
      end
    end)

    assert :ok =
             Drop.run(
               [dir],
               @conn |> Map.put(:server, "3") |> Map.put(:host, "landing.example.com")
             )
  end

  test "creates the app from --subdomain and base domain", %{dir: dir} do
    slug = Path.basename(dir)
    drops_path = "/api/v1/apps/#{slug}/drops"

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{"data" => []})

        {"POST", "/api/v1/apps"} ->
          body = Jason.decode!(Req.Test.raw_body(conn))
          assert body["host"] == "exemplo.sites.example.com"

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 9, "slug" => slug}})

        {"POST", ^drops_path} ->
          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 10, "status" => "queued"}})
      end
    end)

    assert :ok =
             Drop.run(
               [dir],
               @conn
               |> Map.put(:server, "3")
               |> Map.put(:subdomain, "exemplo")
               |> Map.put(:base_domain, "sites.example.com")
             )
  end

  test "publishes a single HTML file as index.html at the site root" do
    file =
      Path.join(
        System.tmp_dir!(),
        "almanaque_#{System.unique_integer([:positive])}.html"
      )

    File.write!(file, "<html>almanaque</html>")
    on_exit(fn -> File.rm(file) end)

    slug = Path.basename(file) |> Path.rootname() |> String.replace("_", "-")
    drops_path = "/api/v1/apps/#{slug}/drops"

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{"data" => []})

        {"POST", "/api/v1/apps"} ->
          body = Jason.decode!(Req.Test.raw_body(conn))
          assert body["runtime"] == "static"
          assert body["slug"] == slug

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 11, "slug" => slug}})

        {"POST", ^drops_path} ->
          tarball =
            Path.join(
              System.tmp_dir!(),
              "cleat_test_drop_#{System.unique_integer([:positive])}.tar.gz"
            )

          File.write!(tarball, Req.Test.raw_body(conn))

          {listing, 0} = System.cmd("tar", ["-tzf", tarball])
          assert listing =~ "./index.html"
          refute listing =~ Path.basename(file)

          {content, 0} = System.cmd("tar", ["-xzf", tarball, "-O", "./index.html"])
          assert content =~ "almanaque"

          File.rm(tarball)

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 12, "status" => "queued"}})
      end
    end)

    assert :ok =
             Drop.run(
               [file],
               @conn |> Map.put(:server, "3") |> Map.put(:host, "almanaque.example.com")
             )
  end

  test "errors on a missing path" do
    assert {:error, message} = Drop.run(["/nope/missing"], @conn)
    assert message =~ "not a file or directory"
  end

  test "requires a target when --app is absent", %{dir: dir} do
    assert {:error, message} = Drop.run([dir], @conn)
    assert message =~ "usage"
  end

  test "derives a sites host for a plain html directory" do
    dir = Path.join(System.tmp_dir!(), "cleat-drop-static-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    on_exit(fn -> File.rm_rf(dir) end)

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{"data" => []})

        {"POST", "/api/v1/apps"} ->
          body = Jason.decode!(Req.Test.raw_body(conn))
          expected_slug = Cleat.Slug.from_name(Path.basename(dir))
          assert body["slug"] == expected_slug
          assert body["host"] == expected_slug <> ".sites.example.com"
          assert body["runtime"] == "static"

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 90, "slug" => body["slug"]}})

        {"POST", path} ->
          assert String.ends_with?(path, "/drops")

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 91, "status" => "queued"}})
      end
    end)

    assert :ok =
             Drop.run(
               [dir],
               %{
                 panel: "https://panel.test",
                 token: "tok",
                 server: "5",
                 sites_base_domain: "sites.example.com"
               }
             )
  end

  test "reuses an existing static app by slug" do
    dir = Path.join(System.tmp_dir!(), "cleat-drop-reuse-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    on_exit(fn -> File.rm_rf(dir) end)

    slug = Path.basename(dir)

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{
            "data" => [
              %{"slug" => slug, "runtime" => "static", "host" => "#{slug}.sites.example.com"}
            ]
          })

        {"POST", path} ->
          assert String.ends_with?(path, "/drops")

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 92, "status" => "queued"}})

        other ->
          flunk("unexpected request #{inspect(other)}")
      end
    end)

    assert :ok =
             Drop.run(
               [dir],
               %{
                 panel: "https://panel.test",
                 token: "tok",
                 server: "5",
                 sites_base_domain: "sites.example.com"
               }
             )
  end

  test "reuses an existing static app with no domain configured at all" do
    dir =
      Path.join(System.tmp_dir!(), "cleat-drop-nodomain-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    on_exit(fn -> File.rm_rf(dir) end)

    slug = Path.basename(dir)

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{
            "data" => [%{"slug" => slug, "runtime" => "static", "host" => "#{slug}.sites.test"}]
          })

        {"POST", path} ->
          assert String.ends_with?(path, "/drops")

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 93, "status" => "queued"}})

        other ->
          flunk("unexpected request #{inspect(other)}")
      end
    end)

    assert :ok =
             Drop.run(
               [dir],
               %{panel: "https://panel.test", token: "tok", server: "5"}
             )
  end

  test "errors when --host was requested but the existing static app is on another host" do
    dir =
      Path.join(System.tmp_dir!(), "cleat-drop-host-reuse-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    on_exit(fn -> File.rm_rf(dir) end)

    slug = Path.basename(dir)

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{
            "data" => [%{"slug" => slug, "runtime" => "static", "host" => "old.example.com"}]
          })

        other ->
          flunk("unexpected request #{inspect(other)}")
      end
    end)

    assert {:error, message} =
             Drop.run(
               [dir],
               %{
                 panel: "https://panel.test",
                 token: "tok",
                 server: "5",
                 host: "new.example.com"
               }
             )

    assert message =~ "already exists"
    assert message =~ "old.example.com"
  end

  test "errors when the slug exists with another runtime" do
    dir =
      Path.join(System.tmp_dir!(), "cleat-drop-conflict-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    on_exit(fn -> File.rm_rf(dir) end)

    slug = Path.basename(dir)

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{
            "data" => [
              %{"slug" => slug, "runtime" => "phoenix", "host" => "#{slug}.apps.example.com"}
            ]
          })

        other ->
          flunk("unexpected request #{inspect(other)}")
      end
    end)

    assert {:error, message} =
             Drop.run(
               [dir],
               %{
                 panel: "https://panel.test",
                 token: "tok",
                 server: "5",
                 sites_base_domain: "sites.example.com"
               }
             )

    assert message =~ "already exists"
  end

  test "still requires a host for a non-static target" do
    dir = Path.join(System.tmp_dir!(), "cleat-drop-build-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "package.json"), ~s({"name":"x"}))
    on_exit(fn -> File.rm_rf(dir) end)

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"data" => []})
    end)

    assert {:error, message} =
             Drop.run(
               [dir],
               %{
                 panel: "https://panel.test",
                 token: "tok",
                 server: "5",
                 sites_base_domain: "sites.example.com"
               }
             )

    assert message =~ "usage"
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
