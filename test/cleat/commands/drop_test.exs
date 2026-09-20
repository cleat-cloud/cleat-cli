defmodule Cleat.Commands.DropTest do
  use ExUnit.Case, async: false

  alias Cleat.Commands.Drop

  @conn %{panel: "https://panel.test", token: "tok"}

  setup do
    dir = Path.join(System.tmp_dir!(), "cleat_drop_cmd_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "index.html"), "<html>hi</html>")
    File.write!(Path.join(dir, "style.css"), "body{}")

    on_exit(fn -> File.rm_rf(dir) end)

    Application.put_env(:cleat_cli, :req_plug, {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:cleat_cli, :req_plug) end)

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
end
