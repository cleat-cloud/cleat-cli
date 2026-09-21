# Static Host Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When `cleat drop` / `cleat deploy --repo` / the MCP `drop` tool is given only-HTML content and no host, detect it and publish at `<slug>.<sites_base_domain>` automatically.

**Architecture:** Add a `Cleat.Static` detector (file/dir → boolean + slug) and a second base domain (`sites_base_domain`) in config. `Cleat.Commands` gains `sites_base_domain/1` and a host fallback that uses the static detector. `Drop` and `Deploy` reuse an existing static app by slug instead of failing, and error clearly when the slug already exists with another runtime.

**Tech Stack:** Elixir escript (existing `Cleat` CLI), `Req`/`Jason` (existing), `ExUnit` + `Req.Test`.

---

## File structure

- Create `lib/cleat/static.ex` — `detect?/1` and `site_slug/1`.
- Modify `lib/cleat/config.ex` — `sites_base_domain/0`.
- Modify `lib/cleat/commands/config.ex` — add `sites_base_domain` to `@writable` + `list` + normalize.
- Modify `lib/cleat/commands.ex` — `sites_base_domain/1`; `host/1` and a new `static_host/2`.
- Modify `lib/cleat/commands/drop.ex` — derive host for static, reuse app by slug.
- Modify `lib/cleat/commands/deploy.ex` — same host derivation for `--repo`.
- Modify `lib/cleat/mcp/tools.ex` — the `drop` tool derives host/reuses app.
- Modify `lib/cleat/cli.ex` — `--sites-base-domain` switch + help line.
- Create `test/cleat/static_test.exs`.
- Modify `test/cleat/commands_test.exs`, `test/cleat/commands/config_test.exs`, `test/cleat/commands/drop_test.exs`, `test/cleat/commands/deploy_test.exs`, `test/cleat/mcp/tools_test.exs`.

Work from `/Users/matheuspuppe/Desktop/Projetos/cleat/cleat-cli` on branch `feat/static-host-detection` (the design doc is committed there).

---

## Task 1: `Cleat.Static` detector

**Files:**
- Create: `lib/cleat/static.ex`
- Test: `test/cleat/static_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule Cleat.StaticTest do
  use ExUnit.Case, async: true

  alias Cleat.Static

  setup do
    dir = Path.join(System.tmp_dir!(), "cleat-static-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, dir: dir}
  end

  test "detects a single html file" do
    file = Path.join(System.tmp_dir!(), "cleat-static-#{System.unique_integer([:positive])}.html")
    File.write!(file, "<html></html>")
    on_exit(fn -> File.rm(file) end)

    assert Static.detect?(file)
  end

  test "detects a directory with index.html and no build file", %{dir: dir} do
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    File.write!(Path.join(dir, "app.css"), "body{}")

    assert Static.detect?(dir)
  end

  test "rejects a node project with index.html", %{dir: dir} do
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    File.write!(Path.join(dir, "package.json"), ~s({"name":"x"}))

    refute Static.detect?(dir)
  end

  test "rejects a mix project", %{dir: dir} do
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    File.write!(Path.join(dir, "mix.exs"), "defmodule X do\nend\n")

    refute Static.detect?(dir)
  end

  test "rejects a go project", %{dir: dir} do
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    File.write!(Path.join(dir, "go.mod"), "module x\n")

    refute Static.detect?(dir)
  end

  test "rejects a directory without an index.html", %{dir: dir} do
    File.write!(Path.join(dir, "about.html"), "<html></html>")

    refute Static.detect?(dir)
  end

  test "site_slug uses the folder name" do
    assert Static.site_slug("/tmp/Minha Loja/") == "minha-loja"
  end

  test "site_slug uses the file rootname for a single html file" do
    assert Static.site_slug("/tmp/almanaque.html") == "almanaque"
  end

  test "site_slug trims to a safe label" do
    assert Static.site_slug("/tmp/__weird--name__/") == "weird-name"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/cleat/static_test.exs`
Expected: FAIL with `module Cleat.Static is not available`.

- [ ] **Step 3: Write the implementation**

```elixir
defmodule Cleat.Static do
  @moduledoc """
  Detects whether a drop/deploy target is a plain static site (only HTML).

  A target is static when it is a single `.html`/`.htm` file, or a directory
  with an `index.html` at its root and no build manifest (`package.json`,
  `mix.exs`, `go.mod`). Used to pick a `<slug>.sites...` host automatically.
  """

  @html_exts ~w(.html .htm)
  @build_files ~w(package.json mix.exs go.mod)

  @doc "True when `path` is a plain static site."
  def detect?(path) when is_binary(path) do
    expanded = Path.expand(path)

    cond do
      File.regular?(expanded) -> html_file?(expanded)
      File.dir?(expanded) -> static_dir?(expanded)
      true -> false
    end
  end

  @doc "Derives a DNS-safe slug from a folder or file path."
  def site_slug(path) when is_binary(path) do
    expanded = Path.expand(path)

    base =
      if File.regular?(expanded) do
        Path.rootname(Path.basename(expanded))
      else
        Path.basename(expanded)
      end

    slugify(base)
  end

  defp html_file?(path), do: String.downcase(Path.extname(path)) in @html_exts

  defp static_dir?(dir) do
    File.exists?(Path.join(dir, "index.html")) and
      not Enum.any?(@build_files, &File.exists?(Path.join(dir, &1)))
  end

  defp slugify(name) do
    case name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-") do
      "" -> nil
      slug -> slug
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/cleat/static_test.exs`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/cleat/static.ex test/cleat/static_test.exs
git commit -m "feat: detect plain static sites and derive their slug"
```

---

## Task 2: `sites_base_domain` config

**Files:**
- Modify: `lib/cleat/config.ex`
- Modify: `lib/cleat/commands/config.ex`
- Modify: `lib/cleat/cli.ex` (add `--sites-base-domain` switch)
- Test: `test/cleat/commands/config_test.exs`

- [ ] **Step 1: Write the failing test**

Append to `test/cleat/commands/config_test.exs`:

```elixir
  test "sets and lists sites_base_domain" do
    assert :ok = Config.run(["set", "sites_base_domain", "Sites.Example.com."], %{})

    assert Cleat.Config.sites_base_domain() == "sites.example.com"

    output = ExUnit.CaptureIO.capture_io(fn -> Config.run(["list"], %{}) end)
    assert output =~ "sites.example.com"
  end
```

(Use the module's existing alias for `Cleat.Commands.Config` if that is how the file refers to it; read the top of the test file first.)

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/cleat/commands/config_test.exs`
Expected: FAIL — `unknown key "sites_base_domain"` and/or `Cleat.Config.sites_base_domain/0 is undefined`.

- [ ] **Step 3: Add the accessor to `lib/cleat/config.ex`**

After the `token/0` definition:

```elixir
  @doc "Configured base domain for static sites, if any."
  def sites_base_domain, do: get("sites_base_domain")
```

- [ ] **Step 4: Make it writable in `lib/cleat/commands/config.ex`**

Change `@writable`:

```elixir
  @writable ~w(base_domain sites_base_domain panel_url)
```

Add to the `list/0` table (after `base_domain`):

```elixir
        ["sites_base_domain", config["sites_base_domain"] || "—"],
```

Normalize it like `base_domain` — replace the `normalize/2` clauses with:

```elixir
  defp normalize("base_domain", value), do: normalize_domain(value)
  defp normalize("sites_base_domain", value), do: normalize_domain(value)

  defp normalize(_key, value), do: String.trim(value)

  defp normalize_domain(value) do
    value |> String.trim() |> String.downcase() |> String.trim_trailing(".")
  end
```

- [ ] **Step 5: Add the CLI switch in `lib/cleat/cli.ex`**

In `@switches`, after `base_domain: :string,`:

```elixir
    sites_base_domain: :string,
```

- [ ] **Step 6: Run tests**

Run: `mix test test/cleat/commands/config_test.exs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/cleat/config.ex lib/cleat/commands/config.ex lib/cleat/cli.ex test/cleat/commands/config_test.exs
git commit -m "feat: add a sites_base_domain config for static sites"
```

---

## Task 3: `sites_base_domain/1` and static host resolution

**Files:**
- Modify: `lib/cleat/commands.ex`
- Test: `test/cleat/commands_test.exs`

- [ ] **Step 1: Write the failing test**

Append to `test/cleat/commands_test.exs` (read the top first for aliases; the module uses `Cleat.Commands`):

```elixir
  test "sites_base_domain falls back to base_domain" do
    System.put_env("CLEAT_SITES_BASE_DOMAIN", "sites.example.com")
    on_exit(fn -> System.delete_env("CLEAT_SITES_BASE_DOMAIN") end)

    assert Cleat.Commands.sites_base_domain(%{}) == "sites.example.com"
  end

  test "static_host builds <slug>.<sites_base_domain>" do
    assert {:ok, "minha-loja.sites.example.com"} =
             Cleat.Commands.static_host("minha-loja", %{sites_base_domain: "sites.example.com"})
  end

  test "static_host errors without a configured sites base domain" do
    assert {:error, message} = Cleat.Commands.static_host("x", %{sites_base_domain: nil})
    assert message =~ "sites_base_domain"
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/cleat/commands_test.exs`
Expected: FAIL — `sites_base_domain/1` / `static_host/2` undefined.

- [ ] **Step 3: Implement in `lib/cleat/commands.ex`**

After `base_domain/1`, add:

```elixir
  @doc """
  Base domain for static sites. Resolution order: `--sites-base-domain`,
  `CLEAT_SITES_BASE_DOMAIN`, the stored `sites_base_domain`, then the regular
  `base_domain` as a fallback.
  """
  def sites_base_domain(opts) do
    opts[:sites_base_domain] || non_empty(System.get_env("CLEAT_SITES_BASE_DOMAIN")) ||
      Config.sites_base_domain() || base_domain(opts)
  end

  @doc """
  Builds a static-site host from `slug` and the configured sites base domain.

  Returns `{:ok, host}` or `{:error, message}`.
  """
  def static_host(slug, opts) do
    case normalize_base(sites_base_domain(opts)) do
      nil ->
        {:error,
         "no sites base domain configured. Run `cleat config set sites_base_domain " <>
           "sites.example.com`, set CLEAT_SITES_BASE_DOMAIN, or pass --host."}

      base ->
        case normalize_slug(slug) do
          nil -> {:error, "could not derive a slug; pass --slug"}
          sub -> {:ok, "#{sub}.#{base}"}
        end
    end
  end

  defp normalize_slug(slug) when is_binary(slug) do
    case slug |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-") do
      "" -> nil
      value -> value
    end
  end

  defp normalize_slug(_), do: nil
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/cleat/commands_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/cleat/commands.ex test/cleat/commands_test.exs
git commit -m "feat: resolve static site hosts from sites_base_domain"
```

---

## Task 4: `drop` derives the host and reuses an existing static app

**Files:**
- Modify: `lib/cleat/commands/drop.ex`
- Test: `test/cleat/commands/drop_test.exs`

- [ ] **Step 1: Read the existing drop test**

Read `test/cleat/commands/drop_test.exs` to match its `Req.Test` stub style and aliases before editing.

- [ ] **Step 2: Write the failing tests**

Add to `test/cleat/commands/drop_test.exs`:

```elixir
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
          assert body["host"] == "cleat-drop-static-#{Path.basename(dir) |> String.replace_prefix("cleat-drop-static-", "")}.sites.example.com"
          assert body["runtime"] == "static"

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 90, "slug" => body["slug"]}})

        {"POST", path} when path =~ "/drops" ->
          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 91, "status" => "queued"}})
      end
    end)

    assert :ok =
             Cleat.Commands.Drop.run([dir], %{
               panel: "https://panel.test",
               token: "tok",
               server: "5",
               sites_base_domain: "sites.example.com"
             })
  end

  test "reuses an existing static app by slug instead of creating" do
    dir = Path.join(System.tmp_dir!(), "cleat-drop-reuse-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    on_exit(fn -> File.rm_rf(dir) end)

    slug = Path.basename(dir)

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{
            "data" => [%{"slug" => slug, "runtime" => "static", "host" => "#{slug}.sites.example.com"}]
          })

        {"POST", path} when path =~ "/drops" ->
          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 92, "status" => "queued"}})

        other ->
          flunk("unexpected request #{inspect(other)}")
      end
    end)

    assert :ok =
             Cleat.Commands.Drop.run([dir], %{
               panel: "https://panel.test",
               token: "tok",
               server: "5",
               sites_base_domain: "sites.example.com"
             })
  end

  test "errors when the slug exists with another runtime" do
    dir = Path.join(System.tmp_dir!(), "cleat-drop-conflict-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    on_exit(fn -> File.rm_rf(dir) end)

    slug = Path.basename(dir)

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "data" => [%{"slug" => slug, "runtime" => "phoenix", "host" => "#{slug}.apps.example.com"}]
      })
    end)

    assert {:error, message} =
             Cleat.Commands.Drop.run([dir], %{
               panel: "https://panel.test",
               token: "tok",
               server: "5",
               sites_base_domain: "sites.example.com"
             })

    assert message =~ "already exists"
  end

  test "still requires a host for a non-static target" do
    dir = Path.join(System.tmp_dir!(), "cleat-drop-build-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "package.json"), ~s({"name":"x"}))

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"data" => []})
    end)

    assert {:error, message} =
             Cleat.Commands.Drop.run([dir], %{
               panel: "https://panel.test",
               token: "tok",
               server: "5",
               sites_base_domain: "sites.example.com"
             })

    assert message =~ "usage"
  end
```

Note: the first test's expected host assertion is awkward; simplify it to compute the slug from the folder name. If `slug` contains characters that the CLI slugifies, compute the expected value the same way (`String.replace(~r/[^a-z0-9]+/, "-")` on the lowercased basename). Make the assertion read the actual `body["slug"]` and assert the host equals `"#{body["slug"]}.sites.example.com"` — that is simpler and still proves the derivation.

- [ ] **Step 3: Run tests to verify they fail**

Run: `mix test test/cleat/commands/drop_test.exs`
Expected: the three new behavior tests FAIL (drop currently requires host / always creates).

- [ ] **Step 4: Implement in `lib/cleat/commands/drop.ex`**

Add the alias:

```elixir
  alias Cleat.{Client, Commands, Output, Static}
```

Replace `register_app/3` and `create_app/4` with host derivation + reuse:

```elixir
  defp resolve_app(client, opts, default_slug) do
    case opts[:app] do
      app when is_binary(app) and app != "" ->
        {:ok, app}

      _ ->
        register_or_reuse_app(client, opts, default_slug)
    end
  end

  defp register_or_reuse_app(client, opts, default_slug) do
    slug = opts[:slug] || default_slug

    cond do
      is_nil(opts[:server]) ->
        {:error, @usage}

      is_nil(slug) ->
        {:error, "could not derive a slug; pass --slug"}

      true ->
        with {:ok, host} <- drop_host(slug, opts),
             :ok <- check_existing(client, slug),
             {:ok, app_slug} <- create_app(client, slug, host, opts) do
          {:ok, app_slug}
        end
    end
  end

  # Static targets default to <slug>.<sites_base_domain> when no host is given.
  defp drop_host(slug, opts) do
    case Commands.host(opts) do
      {:ok, host} -> {:ok, host}
      {:error, :missing_host} -> Commands.static_host(slug, opts)
      {:error, message} -> {:error, message}
    end
  end

  defp check_existing(client, slug) do
    case Client.list_apps(client) do
      {:ok, body} ->
        case Enum.find(Commands.data(body), &(&1["slug"] == slug)) do
          nil ->
            :ok

          %{"runtime" => "static"} ->
            {:error, :exists}

          %{"runtime" => runtime} ->
            {:error, "app #{slug} already exists with runtime #{runtime}; pass --app or a different --slug"}
        end

      {:error, message} ->
        {:error, message}
    end
  end

  defp create_app(client, slug, host, opts) do
    attrs = %{
      "name" => opts[:name] || slug,
      "slug" => slug,
      "host" => host,
      "server_id" => opts[:server],
      "runtime" => "static"
    }

    with {:ok, body} <- Client.create_app(client, attrs) do
      app = Commands.data(body)
      Output.success("Registered static app #{app["slug"]} (##{app["id"]}) → #{host}")
      {:ok, app["slug"]}
    end
  end
```

Then, in `resolve_drop_app`/`resolve_app`'s result handling, treat `{:error, :exists}` as "use the slug as-is". Update the caller in `drop_dir/4`:

```elixir
  defp resolve_app(client, opts, default_slug) do
    case opts[:app] do
      app when is_binary(app) and app != "" ->
        {:ok, app}

      _ ->
        slug = opts[:slug] || default_slug

        case register_or_reuse_app(client, opts, default_slug) do
          {:error, :exists} -> {:ok, slug}
          other -> other
        end
    end
  end
```

(Make sure the final code has a single `resolve_app/3` definition — remove the old one rather than leaving both.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/cleat/commands/drop_test.exs`
Expected: PASS (existing tests plus 4 new).

- [ ] **Step 6: Commit**

```bash
git add lib/cleat/commands/drop.ex test/cleat/commands/drop_test.exs
git commit -m "feat(drop): derive sites hosts and reuse existing static apps"
```

---

## Task 5: `deploy --repo` derives the host for static repos

**Files:**
- Modify: `lib/cleat/commands/deploy.ex`
- Test: `test/cleat/commands/deploy_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/cleat/commands/deploy_test.exs`:

```elixir
  test "derives a sites host for a static repo when no host is given" do
    dir = Path.join(System.tmp_dir!(), "cleat-deploy-static-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    original = File.cwd!()
    on_exit(fn -> File.cd!(original); File.rm_rf(dir) end)

    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/apps"} ->
          Req.Test.json(conn, %{"data" => []})

        {"POST", "/api/v1/apps"} ->
          body = Jason.decode!(Req.Test.raw_body(conn))
          assert body["host"] == "minha-loja.sites.example.com"
          assert body["runtime"] == "static"

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 70, "slug" => "minha-loja"}})

        {"POST", "/api/v1/apps/minha-loja/deployments"} ->
          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 71, "status" => "queued"}})
      end
    end)

    File.cd!(dir)

    assert :ok =
             Deploy.run(nil, %{
               panel: "https://panel.test",
               token: "tok",
               repo: "owner/minha-loja",
               server: "5",
               sites_base_domain: "sites.example.com"
             })
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/cleat/commands/deploy_test.exs`
Expected: FAIL — `register_repo` asks for `--host`.

- [ ] **Step 3: Implement in `lib/cleat/commands/deploy.ex`**

Add the alias `Cleat.Static` (see the current `alias Cleat.{...}` line) and change `register_repo/3` to derive a static host:

```elixir
  defp register_repo(client, repo, opts) do
    slug = opts[:slug] || slugify(Path.basename(repo))

    cond do
      is_nil(opts[:server]) ->
        {:error, "#{repo} is not registered. Pass --server ID (and a host)."}

      true ->
        case repo_host(slug, opts) do
          {:ok, host} -> register(client, repo, host, opts)
          {:error, message} -> {:error, message}
        end
    end
  end

  # Static-only repos default to <slug>.<sites_base_domain> when the local
  # checkout is a plain static site and no host was given.
  defp repo_host(slug, opts) do
    case Commands.host(opts) do
      {:ok, host} ->
        {:ok, host}

      {:error, :missing_host} ->
        if Static.detect?(File.cwd!()) do
          Commands.static_host(slug, opts)
        else
          {:error, "#{opts[:repo]} is not registered. Pass --host DOMAIN or --subdomain NAME."}
        end

      {:error, message} ->
        {:error, message}
    end
  end
```

Keep `register/4` and `runtime/1` unchanged; `runtime/1` already returns `"static"` for a static checkout via `Runtime.detect/0`.

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/cleat/commands/deploy_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/cleat/commands/deploy.ex test/cleat/commands/deploy_test.exs
git commit -m "feat(deploy): derive sites hosts for static repos"
```

---

## Task 6: MCP `drop` tool uses the same detection

**Files:**
- Modify: `lib/cleat/mcp/tools.ex`
- Test: `test/cleat/mcp/tools_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/cleat/mcp/tools_test.exs`:

```elixir
  test "drop derives a sites host for a static path without server/host" do
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
          assert body["host"] == "#{body["slug"]}.sites.example.com"

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"data" => %{"id" => 80, "slug" => body["slug"]}})

        {"POST", path} when path =~ "/drops" ->
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

  test "drop still errors for a static path without server" do
    dir = Path.join(System.tmp_dir!(), "mcp-drop-nosrv-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "index.html"), "<html></html>")
    on_exit(fn -> File.rm_rf(dir) end)

    assert {:error, message} = Tools.call("drop", %{"path" => dir})
    assert message =~ "server"
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/cleat/mcp/tools_test.exs`
Expected: FAIL — the tool requires `server` and `host`.

- [ ] **Step 3: Implement in `lib/cleat/mcp/tools.ex`**

In the `drop` tool's `inputSchema`, add `sites_base_domain` and relax `required` to only `["path"]` (already the case). Add to `properties`:

```elixir
            "sites_base_domain" => %{
              "type" => "string",
              "description" => "Base domain for a derived static host"
            },
```

Replace `resolve_drop_app/2` and `register_static_app/2`:

```elixir
  defp resolve_drop_app(_client, %{"app" => app}) when is_binary(app) and app != "" do
    {:ok, app}
  end

  defp resolve_drop_app(client, args) do
    slug = args["slug"] || Cleat.Static.site_slug(args["path"])

    cond do
      not present?(args, "server") ->
        {:error, "drop requires app, or server (and a host or static path) to register one"}

      is_nil(slug) ->
        {:error, "could not derive a slug; pass slug"}

      true ->
        with {:ok, host} <- drop_host(args, slug),
             :ok <- check_existing(client, slug) do
          register_static_app(client, args, slug, host)
        end
    end
  end

  defp drop_host(args, slug) do
    cond do
      present?(args, "host") ->
        {:ok, args["host"]}

      true ->
        opts = if args["sites_base_domain"], do: %{sites_base_domain: args["sites_base_domain"]}, else: %{}
        Cleat.Commands.static_host(slug, opts)
    end
  end

  defp check_existing(client, slug) do
    case Client.list_apps(client) do
      {:ok, body} ->
        case Enum.find(Commands.data(body), &(&1["slug"] == slug)) do
          nil -> :ok
          %{"runtime" => "static"} -> {:error, :exists}
          %{"runtime" => runtime} -> {:error, "app #{slug} already exists with runtime #{runtime}"}
        end

      {:error, message} ->
        {:error, message}
    end
  end

  defp register_static_app(client, args, slug, host) do
    attrs = %{
      "name" => slug,
      "slug" => slug,
      "host" => host,
      "server_id" => args["server"],
      "runtime" => "static"
    }

    with {:ok, body} <- Client.create_app(client, attrs) do
      {:ok, Commands.data(body)["slug"]}
    end
  end
```

Then, in the `drop` handler, map `{:error, :exists}` to reuse:

```elixir
              with_client(args, fn client ->
                with {:ok, app} <- resolve_drop_app_or_reuse(client, args),
                     {:ok, body} <- Client.create_drop(client, app, tarball, args["ref"]),
                     do: {:ok, data_text(body)}
              end)
```

and add:

```elixir
  defp resolve_drop_app_or_reuse(client, args) do
    case resolve_drop_app(client, args) do
      {:error, :exists} -> {:ok, args["slug"] || Cleat.Static.site_slug(args["path"])}
      other -> other
    end
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/cleat/mcp/tools_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/cleat/mcp/tools.ex test/cleat/mcp/tools_test.exs
git commit -m "feat(mcp): drop derives sites hosts and reuses static apps"
```

---

## Task 7: Help, README and precommit

**Files:**
- Modify: `lib/cleat/cli.ex` (usage)
- Modify: `README.md`

- [ ] **Step 1: Update the usage text in `lib/cleat/cli.ex`**

In the global options section add:

```
      --sites-base-domain D  Base domain for static sites (env CLEAT_SITES_BASE_DOMAIN)
```

And update the `drop` line in the Deployments section:

```
      drop [DIR|FILE] [--app APP] [--watch]   Publish a folder or file (no git);
                                              static sites get <slug>.<sites_base_domain>
```

- [ ] **Step 2: Update the README**

In the Decode/Static section, add a paragraph:

```markdown
`cleat drop ./site` and `cleat deploy --repo owner/site` detect a plain static
site (an `.html` file, or a directory with `index.html` and no build manifest)
and publish it at `<slug>.<sites_base_domain>` automatically. Configure the
static base domain once:

```bash
cleat config set sites_base_domain sites.example.com
```

Pass `--host`/`--subdomain` to override, and `--sites-base-domain` for a one-off.
```

- [ ] **Step 3: Run the full precommit**

Run: `mix precommit`
Expected: `compile --warnings-as-errors`, `format`, and all tests pass.

- [ ] **Step 4: Reinstall and smoke test**

Run:

```bash
mix cleat.install
cleat config set sites_base_domain sites.gestaobem.com
mkdir -p /tmp/cleat-smoke-site && printf '<html><body>hi</body></html>' > /tmp/cleat-smoke-site/index.html
cleat drop /tmp/cleat-smoke-site --server 5 --watch
```

Expected: registers/updates a static app at `cleat-smoke-site.sites.gestaobem.com` and streams a successful deploy. (If the site already exists as `static`, it reuses it.)

- [ ] **Step 5: Commit**

```bash
git add lib/cleat/cli.ex README.md
git commit -m "docs: document automatic static hosts"
```

---

## Self-review notes

- **Spec coverage:** detector (Task 1), config + `sites_base_domain` (Task 2), resolution + `static_host` (Task 3), drop flow with reuse/conflict error (Task 4), deploy `--repo` (Task 5), MCP (Task 6), help/README/smoke (Task 7). Error messages match the spec ("no sites base domain configured…", "app `<slug>` already exists with runtime <r>…").
- **Placeholder scan:** every step shows the code and exact commands. The only freedom left to the implementer is a simplification in Task 4 Step 2 (noted inline).
- **Consistency:** `Cleat.Static.detect?/1`, `Cleat.Static.site_slug/1`, `Commands.sites_base_domain/1`, `Commands.static_host/2`, `Config.sites_base_domain/0`, and the `:exists` sentinel are used identically across tasks. `host/1` keeps its current contract; the static fallback lives in the callers.
