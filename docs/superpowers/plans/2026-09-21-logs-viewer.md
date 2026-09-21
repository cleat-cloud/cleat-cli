# Log Viewer (app + host) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add filters (`tail`, `since`, `grep`) to app logs and a new host-journal viewer, exposed via the panel API, the `cleat` CLI and MCP.

**Architecture:** The panel generalizes its journal fetcher into `CleatDeploy.Logs` with validated options, and adds `GET /api/v1/servers/:id/logs` alongside the existing app logs route. The CLI passes the filters as query params for `apps logs` and adds `servers logs`; MCP gains `server_logs` and extra props on `apps_logs`.

**Tech Stack:** Elixir/Phoenix (panel, `ecto_sqlite3`), Elixir escript CLI, `Req`, ExUnit.

---

## File structure

**Panel (`/Users/matheuspuppe/Desktop/Projetos/cleat/cleat-web`)**
- Create `lib/cleat_deploy/logs.ex` — `fetch_app/2`, `fetch_server/2`, validated opts → journalctl argv + grep filter.
- Create `test/cleat_deploy/logs_test.exs`.
- Modify `lib/cleat_deploy_web/controllers/api/app_controller.ex` — `logs/2` passes query params.
- Modify `lib/cleat_deploy_web/controllers/api/server_controller.ex` — new `logs/2`.
- Modify `lib/cleat_deploy_web/router.ex` — `GET /api/v1/servers/:id/logs`.
- Modify `test/support/runtime_logs_stub.ex` — allow injecting lines/filters for controller tests.
- Modify `test/cleat_deploy_web/controllers/api/servers_test.exs` (add server logs cases).
- Modify `test/cleat_deploy_web/controllers/api/apps_test.exs` (add filter cases).

**CLI (`/Users/matheuspuppe/Desktop/Projetos/cleat/cleat-cli`)**
- Modify `lib/cleat/client.ex` — `app_logs/3`, `server_logs/3`.
- Modify `lib/cleat/commands/apps.ex` — `logs` passes filters.
- Create `lib/cleat/commands/servers_logs.ex` — `servers logs`.
- Modify `lib/cleat/commands/servers.ex` — dispatch `logs` subcommand.
- Modify `lib/cleat/cli.ex` — switches `--tail`, `--since`, `--grep`, `--unit`; usage.
- Modify `lib/cleat/mcp/tools.ex` — `apps_logs` props; new `server_logs` tool.
- Modify `test/cleat/client_test.exs`, `test/cleat/commands/servers_test.exs`, `test/cleat/commands/apps_test.exs`, `test/cleat/mcp/tools_test.exs`.
- Modify `README.md`.

Two repos, two PRs. Panel first (the CLI depends on its API), then CLI.

---

## TASK GROUP A — Panel

### Task A1: `CleatDeploy.Logs` with validated options

**Files:**
- Create: `lib/cleat_deploy/logs.ex`
- Create: `test/cleat_deploy/logs_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule CleatDeploy.LogsTest do
  use CleatDeploy.DataCase, async: false

  alias CleatDeploy.Logs
  alias CleatDeploy.TenancyFixtures

  setup do
    scope = TenancyFixtures.scope_fixture()
    server = TenancyFixtures.server_fixture(scope)
    %{scope: scope, server: server}
  end

  test "builds a default app journal argv", %{scope: scope, server: server} do
    app = TenancyFixtures.app_fixture(scope, server, %{slug: "assistente", systemd_unit: "assistente"})

    assert {:ok, result} = Logs.fetch_app(app, %{})
    assert result.unit == "assistente"
    assert is_list(result.lines)
  end

  test "argv_for/2 includes tail, since and unit" do
    argv = Logs.argv_for(%{unit: "caddy", tail: 50, since: "1h"})

    assert argv == [
             "sudo",
             "journalctl",
             "-u",
             "caddy",
             "-n",
             "50",
             "--since",
             "1h",
             "--no-pager",
             "-o",
             "short-iso",
             "--utc"
           ]
  end

  test "argv_for/2 without unit reads the whole host journal" do
    argv = Logs.argv_for(%{unit: nil, tail: 200, since: nil})
    assert "-u" not in argv
    assert "200" in argv
    refute "--since" in argv
  end

  test "validates tail bounds" do
    assert {:error, message} = Logs.normalize(%{tail: 0})
    assert message =~ "tail"
    assert {:error, _} = Logs.normalize(%{tail: 100_000})
  end

  test "validates since format" do
    assert {:ok, _} = Logs.normalize(%{since: "30m"})
    assert {:ok, _} = Logs.normalize(%{since: "2h"})
    assert {:ok, _} = Logs.normalize(%{since: "2026-09-21"})
    assert {:ok, _} = Logs.normalize(%{since: "2026-09-21 14:30"})
    assert {:error, message} = Logs.normalize(%{since: "yesterday; rm -rf /"})
    assert message =~ "since"
  end

  test "validates unit against the allowlist" do
    assert {:ok, _} = Logs.normalize(%{unit: "node-lumina.service"})
    assert {:error, message} = Logs.normalize(%{unit: "atelie; rm -rf /"})
    assert message =~ "unit"
  end

  test "grep filters lines as a substring", %{scope: scope, server: server} do
    app = TenancyFixtures.app_fixture(scope, server, %{slug: "assistente", systemd_unit: "assistente"})

    assert {:ok, result} = Logs.fetch_app(app, %{grep: "started"})
    assert Enum.all?(result.lines, &String.contains?(&1, "started"))
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/cleat_deploy/logs_test.exs`
Expected: FAIL — `CleatDeploy.Logs` is not available.

- [ ] **Step 3: Write the implementation**

Create `lib/cleat_deploy/logs.ex`:

```elixir
defmodule CleatDeploy.Logs do
  @moduledoc """
  Fetches systemd journal lines for an app's unit or a whole server (host).

  Options are validated here (the API trusts this as the source of truth) and the
  journal command is built as an argv list — never a shell string. `grep` is a
  plain substring filter applied to the fetched lines, not a server-side regex.
  """

  alias CleatDeploy.Apps.App
  alias CleatDeploy.Repo

  @default_tail 200
  @max_tail 5000
  @unit_pattern ~r/^[A-Za-z0-9:_.@-]+$/
  @since_iso ~r/^\d{4}-\d{2}-\d{2}([ T]\d{2}:\d{2}(:\d{2})?)?$/
  @since_rel ~r/^\d+(s|m|h|d|w)$/
  @max_grep 200

  @callback run(server :: term(), app :: term(), argv :: [String.t()]) ::
              {:ok, String.t()} | {:error, term()}

  @doc "Fetches journal lines for an app's unit."
  def fetch_app(%App{} = app, opts) do
    app = Repo.preload(app, :server)
    unit = app.systemd_unit || App.default_systemd_unit(app.slug, app.runtime || "phoenix")

    with {:ok, opts} <- normalize(Map.put(opts, :unit, unit)) do
      run_and_wrap(app.server, app, opts, unit)
    end
  end

  @doc "Fetches journal lines for a server (whole host when no unit is given)."
  def fetch_server(server, opts) do
    with {:ok, opts} <- normalize(opts) do
      run_and_wrap(server, nil, opts, opts[:unit])
    end
  end

  @doc "Validates options, returning `{:ok, normalized}` or `{:error, message}`."
  def normalize(opts) when is_map(opts) do
    with {:ok, unit} <- normalize_unit(Map.get(opts, :unit)),
         {:ok, since} <- normalize_since(Map.get(opts, :since)),
         {:ok, tail} <- normalize_tail(Map.get(opts, :tail)),
         {:ok, grep} <- normalize_grep(Map.get(opts, :grep)) do
      {:ok, %{unit: unit, since: since, tail: tail, grep: grep}}
    end
  end

  @doc "Builds the `journalctl` argv for normalized options."
  def argv_for(%{tail: tail} = opts) do
    base = ["sudo", "journalctl"]

    unit = if opts[:unit], do: ["-u", opts[:unit]], else: []
    since = if opts[:since], do: ["--since", opts[:since]], else: []

    base ++ unit ++ ["-n", Integer.to_string(tail)] ++ since ++ ["--no-pager", "-o", "short-iso", "--utc"]
  end

  defp run_and_wrap(server, app, opts, unit) do
    case client().run(server, app, argv_for(opts)) do
      {:ok, output} ->
        lines =
          output
          |> split_lines()
          |> apply_grep(opts[:grep])

        {:ok, %{unit: unit, lines: lines, fetched_at: DateTime.utc_now(:second)}}

      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp apply_grep(lines, nil), do: lines
  defp apply_grep(lines, ""), do: lines
  defp apply_grep(lines, needle), do: Enum.filter(lines, &String.contains?(&1, needle))

  defp normalize_unit(nil), do: {:ok, nil}
  defp normalize_unit(""), do: {:ok, nil}

  defp normalize_unit(unit) when is_binary(unit) do
    if byte_size(unit) <= 128 and Regex.match?(@unit_pattern, unit) do
      {:ok, unit}
    else
      {:error, "invalid unit"}
    end
  end

  defp normalize_unit(_), do: {:error, "invalid unit"}

  defp normalize_since(nil), do: {:ok, nil}
  defp normalize_since(""), do: {:ok, nil}

  defp normalize_since(since) when is_binary(since) do
    if byte_size(since) <= 32 and (Regex.match?(@since_iso, since) or Regex.match?(@since_rel, since)) do
      {:ok, since}
    else
      {:error, "invalid since (use 30m, 2h, 1d or 2026-09-21)"}
    end
  end

  defp normalize_since(_), do: {:error, "invalid since (use 30m, 2h, 1d or 2026-09-21)"}

  defp normalize_tail(nil), do: {:ok, @default_tail}
  defp normalize_tail(""), do: {:ok, @default_tail}

  defp normalize_tail(tail) when is_integer(tail) do
    if tail >= 1 and tail <= @max_tail do
      {:ok, tail}
    else
      {:error, "tail must be between 1 and #{@max_tail}"}
    end
  end

  defp normalize_tail(tail) when is_binary(tail) do
    case Integer.parse(tail) do
      {int, ""} -> normalize_tail(int)
      _ -> {:error, "tail must be between 1 and #{@max_tail}"}
    end
  end

  defp normalize_tail(_), do: {:error, "tail must be between 1 and #{@max_tail}"}

  defp normalize_grep(nil), do: {:ok, nil}

  defp normalize_grep(grep) when is_binary(grep) and byte_size(grep) <= @max_grep,
    do: {:ok, grep}

  defp normalize_grep(_), do: {:error, "grep is too long"}

  defp client do
    Application.get_env(:cleat_deploy, :runtime_logs, CleatDeploy.Apps.RuntimeLogsSsh)
  end

  defp split_lines(output) when is_binary(output) do
    output
    |> String.split("\n")
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp format_error(reason) when is_binary(reason) do
    trimmed = String.trim(reason)

    cond do
      trimmed == "" -> "Could not read logs from the VM"
      String.length(trimmed) > 400 -> String.slice(trimmed, 0, 400) <> "…"
      true -> trimmed
    end
  end

  defp format_error(reason), do: "Could not read logs from the VM (#{inspect(reason)})"
end
```

Notes:
- The existing `CleatDeploy.Apps.RuntimeLogs` behaviour's callback is `run(app, argv)`. This new module calls `client().run(server, app, argv)` (3 args) so it can serve both app and host. Update the behaviour stub accordingly in Task A4 — for now, make the new module call the existing 2-arity callback for apps and add a 3-arity for servers. Simpler: define this module's own internal adapter that calls the configured client with `(server, argv)` when `app` is nil and `(app, argv)` when app is set:

```elixir
  defp run_command(nil, server, argv), do: client().run(server, argv)
  defp run_command(app, _server, argv), do: client().run(app, argv)
```
  and use `run_command(app, server, argv)` inside `run_and_wrap`. Since `RuntimeLogsSsh.run/2` already takes `(app_or_server, argv)` and only reads `.server`, passing a `%Server{}` there works too (it has a `:server` field? verify: `RuntimeLogsSsh` reads `app.server` — a `%Server{}` does not have `.server`). Therefore prefer the 2-arity with the app for app logs and add `run/2` support for a server by having `RuntimeLogsSsh` accept either an `%App{}` (uses `app.server`) or a `%Server{}` (uses itself). Update `RuntimeLogsSsh` minimally:

```elixir
  defp server_for(%{server: server}), do: server
  defp server_for(server), do: server
```
  and use `server_for(subject)` where it currently does `app.server`. This keeps one code path for local-vs-SSH detection.

- Keep `CleatDeploy.Apps.RuntimeLogs` and its tests working; the new module supersedes it in the controllers but the old module can stay until a later cleanup (do not delete it in this task).

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/cleat_deploy/logs_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/cleat_deploy/logs.ex lib/cleat_deploy/apps/runtime_logs_ssh.ex test/cleat_deploy/logs_test.exs
git commit -m "feat(logs): add a journal fetcher with tail/since/grep/unit"
```

---

### Task A2: Server logs endpoint

**Files:**
- Modify: `lib/cleat_deploy_web/router.ex`
- Modify: `lib/cleat_deploy_web/controllers/api/server_controller.ex`
- Modify: `test/cleat_deploy_web/controllers/api/servers_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/cleat_deploy_web/controllers/api/servers_test.exs`:

```elixir
  test "GET /api/v1/servers/:id/logs returns host journal lines", %{scope: scope, token: token} do
    server = TenancyFixtures.server_fixture(scope)

    conn =
      build_conn()
      |> auth(token)
      |> get(~p"/api/v1/servers/#{server.id}/logs")
      |> json_response(200)

    data = conn["data"]
    assert is_list(data["lines"])
    assert Map.has_key?(data, "fetched_at")
  end

  test "GET /api/v1/servers/:id/logs rejects an unsafe unit", %{scope: scope, token: token} do
    server = TenancyFixtures.server_fixture(scope)

    body =
      build_conn()
      |> auth(token)
      |> get(~p"/api/v1/servers/#{server.id}/logs?unit=evil;rm")
      |> json_response(422)

    assert body["error"] == "invalid_request"
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/cleat_deploy_web/controllers/api/servers_test.exs`
Expected: FAIL (404, route missing).

- [ ] **Step 3: Add the route**

In `lib/cleat_deploy_web/router.ex`, inside the `[:api, :api_auth]` scope, after `get "/servers/:id/resize-options"...`:

```elixir
    get "/servers/:id/logs", ServerController, :logs
```

- [ ] **Step 4: Add the controller action**

In `lib/cleat_deploy_web/controllers/api/server_controller.ex`, add the alias `alias CleatDeploy.Logs` and:

```elixir
  def logs(conn, %{"id" => id} = params) do
    case fetch_server(conn.assigns.current_scope, id) do
      {:ok, server} ->
        case Logs.fetch_server(server, log_opts(params)) do
          {:ok, result} ->
            json(conn, %{
              data: %{unit: result.unit, lines: result.lines, fetched_at: result.fetched_at}
            })

          {:error, message} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "invalid_request", message: message})
        end

      :error ->
        not_found(conn)
    end
  end

  defp log_opts(params) do
    %{
      unit: params["unit"],
      since: params["since"],
      tail: params["tail"],
      grep: params["grep"]
    }
  end
```

Note: distinguish validation errors (422) from remote failures (502). Both come back as `{:error, message}` from `Logs`; simplest correct behavior is 422 for `message =~ "invalid"` or "tail must", else 502. Implement:

```elixir
          {:error, message} ->
            status = if validation_error?(message), do: :unprocessable_entity, else: :bad_gateway
            error = if validation_error?(message), do: "invalid_request", else: "runtime_logs_failed"

            conn
            |> put_status(status)
            |> json(%{error: error, message: message})
```

with:

```elixir
  defp validation_error?(message) do
    String.starts_with?(message, "invalid") or String.starts_with?(message, "tail") or
      String.starts_with?(message, "grep")
  end
```

- [ ] **Step 5: Run tests**

Run: `mix test test/cleat_deploy_web/controllers/api/servers_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/cleat_deploy_web/router.ex lib/cleat_deploy_web/controllers/api/server_controller.ex test/cleat_deploy_web/controllers/api/servers_test.exs
git commit -m "feat(api): expose GET /servers/:id/logs"
```

---

### Task A3: App logs accepts filters

**Files:**
- Modify: `lib/cleat_deploy_web/controllers/api/app_controller.ex`
- Modify: `test/cleat_deploy_web/controllers/api/apps_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/cleat_deploy_web/controllers/api/apps_test.exs` (match the file's existing setup/auth style):

```elixir
  test "GET /api/v1/apps/:app_id/logs accepts since and tail", %{scope: scope, token: token} do
    server = TenancyFixtures.server_fixture(scope)
    app = TenancyFixtures.app_fixture(scope, server, %{slug: "assistente", systemd_unit: "assistente"})

    body =
      build_conn()
      |> auth(token)
      |> get(~p"/api/v1/apps/#{app.slug}/logs?since=1h&tail=50")
      |> json_response(200)

    assert is_list(body["data"]["lines"])
  end

  test "GET /api/v1/apps/:app_id/logs rejects an invalid since", %{scope: scope, token: token} do
    server = TenancyFixtures.server_fixture(scope)
    app = TenancyFixtures.app_fixture(scope, server, %{slug: "assistente", systemd_unit: "assistente"})

    body =
      build_conn()
      |> auth(token)
      |> get(~p"/api/v1/apps/#{app.slug}/logs?since=nope")
      |> json_response(422)

    assert body["error"] == "invalid_request"
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/cleat_deploy_web/controllers/api/apps_test.exs`
Expected: FAIL (invalid since currently ignored / no 422).

- [ ] **Step 3: Update the controller**

In `lib/cleat_deploy_web/controllers/api/app_controller.ex`, change `logs/2` to pass params and use `CleatDeploy.Logs`:

```elixir
  def logs(conn, %{"app_id" => app_id} = params) do
    scope = conn.assigns.current_scope

    with {:ok, app} <- resolve_app(scope, app_id) do
      if app.runtime == "static" do
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "runtime_logs_unavailable"})
      else
        fetch_logs(conn, app, params)
      end
    else
      :error -> not_found(conn)
    end
  end

  defp fetch_logs(conn, app, params) do
    opts = %{
      since: params["since"],
      tail: params["tail"],
      grep: params["grep"]
    }

    case CleatDeploy.Logs.fetch_app(app, opts) do
      {:ok, result} ->
        json(conn, %{data: %{unit: result.unit, lines: result.lines, fetched_at: result.fetched_at}})

      {:error, message} ->
        status = if log_validation_error?(message), do: :unprocessable_entity, else: :bad_gateway
        error = if log_validation_error?(message), do: "invalid_request", else: "runtime_logs_failed"

        conn
        |> put_status(status)
        |> json(%{error: error, message: message})
    end
  end

  defp log_validation_error?(message) do
    String.starts_with?(message, "invalid") or String.starts_with?(message, "tail") or
      String.starts_with?(message, "grep")
  end
```

Remove the now-unused old `fetch_logs/2` and any `alias CleatDeploy.Apps` reference only if unused elsewhere (check the file).

- [ ] **Step 4: Run tests**

Run: `mix test test/cleat_deploy_web/controllers/api/apps_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/cleat_deploy_web/controllers/api/app_controller.ex test/cleat_deploy_web/controllers/api/apps_test.exs
git commit -m "feat(api): accept tail/since/grep on app logs"
```

---

### Task A4: Stub supports filters + full panel precommit

**Files:**
- Modify: `test/support/runtime_logs_stub.ex`

- [ ] **Step 1: Read the stub and the `@behaviour`**

Read `test/support/runtime_logs_stub.ex` and `lib/cleat_deploy/apps/runtime_logs_ssh.ex`. Ensure the stub's `run/2` signature still matches whatever the new `CleatDeploy.Logs` calls (Task A1 decides 2-arity with a server-or-app subject). If Task A1 changed the call shape, update the stub and its `@behaviour` accordingly, keeping the existing canned lines.

- [ ] **Step 2: Run the whole panel suite**

Run: `mix precommit`
Expected: compile `--warnings-as-errors`, format, and all tests pass.

- [ ] **Step 3: Commit (if the stub changed)**

```bash
git add test/support/runtime_logs_stub.ex
git commit -m "test(logs): keep the journal stub in sync"
```

---

### Task A5: Panel PR

- [ ] **Step 1: Push and open the PR**

```bash
git checkout -b feat/log-filters
git push -u origin feat/log-filters
gh pr create --base main --head feat/log-filters --title "feat(logs): filters for app logs + host journal endpoint" --body "Adds \`CleatDeploy.Logs\` (validated tail/since/grep/unit, argv-built journalctl, substring grep) and \`GET /api/v1/servers/:id/logs\`. \`/apps/:app_id/logs\` now accepts the same filters and returns 422 for invalid input."
```

- [ ] **Step 2: Wait for CI and report the URL**

Run: `gh pr checks --watch`
Report the PR URL. Do not merge unless asked.

---

## TASK GROUP B — CLI + MCP

Work from `/Users/matheuspuppe/Desktop/Projetos/cleat/cleat-cli`.

### Task B1: Client methods

**Files:**
- Modify: `lib/cleat/client.ex`
- Test: `test/cleat/client_test.exs`

- [ ] **Step 1: Write the failing test**

Read `test/cleat/client_test.exs` for style, then add:

```elixir
  test "app_logs/3 sends the filters as query params" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/apps/lumina/logs"
      assert conn.query_string == "grep=error&since=1h&tail=50"
      Req.Test.json(conn, %{"data" => %{"unit" => "node-lumina", "lines" => [], "fetched_at" => "t"}})
    end)

    client = Cleat.Client.new("https://panel.test", "tok")
    assert {:ok, _} = Cleat.Client.app_logs(client, "lumina", %{since: "1h", tail: 50, grep: "error"})
  end

  test "server_logs/3 hits the server logs path" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/servers/5/logs"
      assert conn.query_string == "tail=100"
      Req.Test.json(conn, %{"data" => %{"unit" => nil, "lines" => [], "fetched_at" => "t"}})
    end)

    client = Cleat.Client.new("https://panel.test", "tok")
    assert {:ok, _} = Cleat.Client.server_logs(client, 5, %{tail: 100})
  end
```

Note: query-string order depends on the implementation; if you build the query with `Req`'s `params:`, the encoder sorts keys alphabetically. Assert the exact string you produce.

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/cleat/client_test.exs`
Expected: FAIL (`app_logs/3` / `server_logs/3` undefined).

- [ ] **Step 3: Implement**

In `lib/cleat/client.ex`, add (keeping `app_logs/2` for compatibility by delegating):

```elixir
  def app_logs(client, app), do: app_logs(client, app, %{})

  def app_logs(%__MODULE__{} = client, app, opts) when is_map(opts) do
    request(client, :get, "/api/v1/apps/#{app}/logs", params: log_params(opts))
  end

  def server_logs(%__MODULE__{} = client, id, opts \\ %{}) when is_map(opts) do
    request(client, :get, "/api/v1/servers/#{id}/logs", params: log_params(opts))
  end

  defp log_params(opts) do
    %{
      "tail" => opts[:tail],
      "since" => opts[:since],
      "grep" => opts[:grep],
      "unit" => opts[:unit]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
```

Check how the existing `list_env/3` builds query params (it already passes `reveal=true`) and match that mechanism (`params:` vs string concat).

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/cleat/client_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/cleat/client.ex test/cleat/client_test.exs
git commit -m "feat(client): app_logs filters and server_logs"
```

---

### Task B2: `apps logs` passes filters

**Files:**
- Modify: `lib/cleat/commands/apps.ex`
- Test: `test/cleat/commands/apps_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/cleat/commands/apps_test.exs`:

```elixir
  test "passes tail, since and grep to the logs request" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/apps/my-app/logs"
      assert conn.query_string =~ "since=1h"
      assert conn.query_string =~ "tail=50"
      assert conn.query_string =~ "grep=error"
      Req.Test.json(conn, %{"data" => %{"unit" => "x", "lines" => ["a"], "fetched_at" => "t"}})
    end)

    assert :ok =
             Apps.run(["logs", "my-app"], %{
               panel: "https://panel.test",
               token: "tok",
               since: "1h",
               tail: 50,
               grep: "error"
             })
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/cleat/commands/apps_test.exs`
Expected: FAIL (filters ignored).

- [ ] **Step 3: Implement**

In `lib/cleat/commands/apps.ex`, change `logs/2` to call `Client.app_logs(client, app, log_opts(opts))` (and the follow loop likewise), where:

```elixir
  defp log_opts(opts) do
    %{tail: opts[:tail], since: opts[:since], grep: opts[:grep]}
  end
```

Update both the initial fetch (`Client.app_logs(client, app)`) and the `follow/4` fetch.

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/cleat/commands/apps_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/cleat/commands/apps.ex test/cleat/commands/apps_test.exs
git commit -m "feat(apps): pass log filters through"
```

---

### Task B3: `servers logs` command

**Files:**
- Create: `lib/cleat/commands/servers_logs.ex`
- Modify: `lib/cleat/commands/servers.ex`
- Test: `test/cleat/commands/servers_test.exs`

- [ ] **Step 1: Write the failing test**

Read `test/cleat/commands/servers_test.exs` for style, then add:

```elixir
  test "servers logs prints host journal lines" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/servers/5/logs"
      assert conn.query_string =~ "since=1h"
      Req.Test.json(conn, %{"data" => %{"unit" => nil, "lines" => ["host line"], "fetched_at" => "t"}})
    end)

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert :ok =
                 Servers.run(["logs", "5"], %{
                   panel: "https://panel.test",
                   token: "tok",
                   since: "1h"
                 })
      end)

    assert output =~ "host line"
  end

  test "servers logs passes unit" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.query_string =~ "unit=caddy"
      Req.Test.json(conn, %{"data" => %{"unit" => "caddy", "lines" => [], "fetched_at" => "t"}})
    end)

    assert :ok =
             Servers.run(["logs", "5"], %{panel: "https://panel.test", token: "tok", unit: "caddy"})
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/cleat/commands/servers_test.exs`
Expected: FAIL (unknown subcommand / no route).

- [ ] **Step 3: Implement**

Create `lib/cleat/commands/servers_logs.ex`:

```elixir
defmodule Cleat.Commands.ServersLogs do
  @moduledoc false

  alias Cleat.{Client, Commands, Output, Poller}

  def run(id, opts) do
    with {:ok, client} <- Commands.client(opts),
         {:ok, body} <- Client.server_logs(client, id, log_opts(opts)) do
      lines = Commands.data(body)["lines"] || []
      Output.info(Enum.join(lines, "\n"))

      if opts[:follow], do: follow(client, id, lines, opts), else: :ok
    end
  end

  defp log_opts(opts), do: %{tail: opts[:tail], since: opts[:since], grep: opts[:grep], unit: opts[:unit]}

  defp follow(client, id, printed, opts) do
    fetch = fn -> Client.server_logs(client, id, log_opts(opts)) end

    step = fn body, printed ->
      lines = Commands.data(body)["lines"] || []
      Enum.each(lines, &IO.puts/1)
      {:continue, lines}
    end

    Poller.poll(fetch, step, printed)
  end
end
```

Note: the interaction with `Poller.poll/4` differs from `apps logs` (which uses a log string delta). Keep follow simple and consistent with `Cleat.Commands.Logs`'s polling; do not over-engineer. If `Poller` requires a specific step shape, read `lib/cleat/poller.ex` and adapt to it (it is used by `deploy`, `logs` and `apps logs`).

In `lib/cleat/commands/servers.ex`, add a dispatch clause:

```elixir
  def run(["logs", id | _rest], opts), do: ServersLogs.run(id, opts)
```

and alias `Cleat.Commands.ServersLogs`. Match the file's existing `run/2` clause order.

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/cleat/commands/servers_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/cleat/commands/servers_logs.ex lib/cleat/commands/servers.ex test/cleat/commands/servers_test.exs
git commit -m "feat(servers): add servers logs"
```

---

### Task B4: CLI switches, usage and MCP tools

**Files:**
- Modify: `lib/cleat/cli.ex`
- Modify: `lib/cleat/mcp/tools.ex`
- Test: `test/cleat/mcp/tools_test.exs`

- [ ] **Step 1: Write the failing tests**

Add to `test/cleat/mcp/tools_test.exs`:

```elixir
  test "apps_logs forwards tail, since and grep" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/apps/lumina/logs"
      assert conn.query_string =~ "grep=error"
      assert conn.query_string =~ "since=1h"
      assert conn.query_string =~ "tail=50"
      Req.Test.json(conn, %{"data" => %{"unit" => "x", "lines" => [], "fetched_at" => "t"}})
    end)

    assert {:ok, _} =
             Tools.call("apps_logs", %{
               "app" => "lumina",
               "since" => "1h",
               "tail" => 50,
               "grep" => "error",
               "panel" => "https://panel.test",
               "token" => "tok"
             })
  end

  test "server_logs hits the server logs endpoint" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/servers/5/logs"
      assert conn.query_string =~ "unit=caddy"
      Req.Test.json(conn, %{"data" => %{"unit" => "caddy", "lines" => [], "fetched_at" => "t"}})
    end)

    assert {:ok, _} =
             Tools.call("server_logs", %{
               "server" => "5",
               "unit" => "caddy",
               "panel" => "https://panel.test",
               "token" => "tok"
             })
  end

  test "server_logs requires server" do
    assert {:error, message} = Tools.call("server_logs", %{})
    assert message =~ "server"
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/cleat/mcp/tools_test.exs`
Expected: `apps_logs` filter assertions FAIL; `server_logs` FAIL (unknown tool).

- [ ] **Step 3: Implement**

1. `lib/cleat/cli.ex`: add switches `tail: :integer`, `since: :string`, `grep: :string`, `unit: :string`. Update usage lines:

```
      apps logs APP [--tail N] [--since S] [--grep T] [--follow]
      servers logs ID [--unit U] [--tail N] [--since S] [--grep T] [--follow]
```

2. `lib/cleat/mcp/tools.ex`:
   - In `apps_logs` schema add `"tail"`, `"since"`, `"grep"` (types integer/string) and pass them in the handler call: `Client.app_logs(client, args["app"], %{tail: args["tail"], since: args["since"], grep: args["grep"]})`.
   - Add a `server_logs` tool:

```elixir
    %{
      "name" => "server_logs",
      "description" => "System journal for a server (all units, or one with unit)",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "server" => %{"type" => "string"},
          "unit" => %{"type" => "string"},
          "tail" => %{"type" => "integer"},
          "since" => %{"type" => "string"},
          "grep" => %{"type" => "string"},
          "panel" => @panel,
          "token" => @token
        },
        "required" => ["server"]
      },
      "handler" => fn args ->
        with_client(args, fn client ->
          opts = %{unit: args["unit"], tail: args["tail"], since: args["since"], grep: args["grep"]}

          with {:ok, body} <- Client.server_logs(client, args["server"], opts),
               do: {:ok, data_text(body)}
        end)
      end
    },
```

- [ ] **Step 4: Run tests**

Run: `mix test test/cleat/mcp/tools_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/cleat/cli.ex lib/cleat/mcp/tools.ex test/cleat/mcp/tools_test.exs
git commit -m "feat(mcp): server_logs and log filters on apps_logs"
```

---

### Task B5: Docs and CLI PR

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the README**

In the commands table, change the `apps logs` row and add `servers logs`:

```markdown
| `cleat apps logs APP` | Runtime logs, with `--tail`, `--since`, `--grep`, `--follow` |
| `cleat servers logs ID` | Host journal, with `--unit`, `--tail`, `--since`, `--grep`, `--follow` |
```

Add a short section:

```markdown
### Logs

```bash
cleat apps logs lumina --tail 500 --since 1h --grep error
cleat servers logs 5 --unit caddy --since 30m
```

`--since` accepts `30m`, `2h`, `1d` or an ISO date (`2026-09-21`,
`2026-09-21 14:30`). `--grep` is a case-sensitive substring filter. Without
`--unit`, `servers logs` shows the whole host journal.
```

- [ ] **Step 2: Run precommit**

Run: `mix precommit`
Expected: all pass.

- [ ] **Step 3: Smoke test against the live panel**

Run:

```bash
mix cleat.install
cleat servers logs 5 --since 1h --tail 20
cleat apps logs lumina --tail 20
cleat apps logs lumina --grep Listening
```

Expected: real journal lines; the grep run shows only matching lines. If the panel deploy from Task Group A is not live yet, note it and re-run after deploying.

- [ ] **Step 4: Commit and open the PR**

```bash
git add README.md
git commit -m "docs: document log filters"
git checkout -b feat/log-filters
git push -u origin feat/log-filters
gh pr create --base main --head feat/log-filters --title "feat: log filters and host journal" --body "Adds tail/since/grep to apps logs, a new servers logs for the host journal, and MCP server_logs. Requires the panel PR (servers/:id/logs) to be deployed."
gh pr checks --watch
```

Report both PR URLs.

---

## Self-review notes

- **Spec coverage:** validated journal fetcher (A1), host endpoint (A2), app filters (A3), stub sync (A4), panel PR (A5); client (B1), apps logs filters (B2), servers logs (B3), CLI switches + MCP tools (B4), docs + smoke + PR (B5). Error mapping 422/502 matches the spec. grep is a substring filter; since accepts ISO and relative.
- **Placeholder scan:** no TBD; each step has code and commands. Two steps deliberately say "read the file and adapt" (A4 stub, B3 Poller) because the exact call shape depends on A1's implementation choice — the plan explains the constraint.
- **Consistency:** `CleatDeploy.Logs.fetch_app/2`, `fetch_server/2`, `normalize/1`, `argv_for/1`; `Cleat.Client.app_logs/3`, `server_logs/3`; tool names `apps_logs`, `server_logs`; switches `--tail/--since/--grep/--unit` are used identically throughout.
- **Ordering:** panel API first (CLI depends on it). The CLI smoke test in B5 requires the panel deployed.
