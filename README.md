# cleat-cli

`cleat` is the command-line client for [Cleat](https://github.com/puppe1990/cleat-deploy),
a self-hosted PaaS that deploys Phoenix/Elixir, Go, Node (Next.js / TanStack
Start), Ruby on Rails and static apps to Hetzner Cloud and AWS Lightsail over
SSH.

It talks to the panel's JSON API (`/api/v1`) to list servers and apps, manage env
vars, trigger deploys, and watch build and runtime logs.

## Install

Requires Elixir 1.15+ / OTP 26+.

```bash
git clone https://github.com/puppe1990/cleat-cli.git
cd cleat-cli
mix deps.get
mix install
```

`mix install` builds the escript and copies it to `~/.local/bin` (override with
`mix install /usr/local/bin` or `CLEAT_INSTALL_DIR`). Make sure the destination
is on your `PATH`, then check `cleat version`.

## Quick start

```bash
# Point at your panel and authenticate. Credentials can be passed as flags.
cleat login --panel https://panel.example.com --email you@example.com

# Inspect what you have access to.
cleat whoami
cleat servers list
cleat apps list

# Trigger a deploy and watch it build.
cleat deploy my-app --watch

# Follow a build log.
cleat logs 42 --follow
```

`cleat login` exchanges your email/password for a personal access token and
stores it in `~/.config/cleat/config.json`. The token is shown only once by the
panel and is stored as a hash server-side.

## Commands

| Command | Description |
|---------|-------------|
| `cleat login` | Authenticate and store a token |
| `cleat logout` | Revoke the token and clear local credentials |
| `cleat whoami` | Show the authenticated user and tenant |
| `cleat init` | Write `.cleat_deploy/deploy.json` in the current project |
| `cleat config` | Show or edit CLI configuration |
| `cleat servers list` | List servers |
| `cleat servers show ID` | Show one server |
| `cleat apps list` | List apps |
| `cleat apps show APP` | Show one app (by id or slug) |
| `cleat apps create` | Create an app |
| `cleat apps update APP` | Edit repo / branch / auto-deploy / host / port / runtime |
| `cleat apps logs APP` | App journal, with `--tail`, `--since`, `--grep`, `--follow` |
| `cleat servers logs ID` | Host journal, with `--unit`, `--tail`, `--since`, `--grep`, `--follow` |
| `cleat env list APP` | List env vars (secrets masked) |
| `cleat env set APP K=V` | Upsert one or more env vars |
| `cleat env unset APP KEY` | Delete an env var |
| `cleat deploy APP` | Trigger a deploy (by id or slug) |
| `cleat deploy --repo O/R` | Register if needed, then deploy |
| `cleat drop [DIR\|FILE]` | Publish a local folder or file, no git (Netlify-Drop style) |
| `cleat cancel APP` | Cancel the active deploy |
| `cleat status APP` | List recent deployments for an app |
| `cleat logs DEPLOYMENT_ID` | Print a deployment's build log |
| `cleat mcp` | Run as a Model Context Protocol server on stdio |

Run `cleat help` for the full option list.

### Agent integration (MCP)

`cleat` can run as a Model Context Protocol server on stdio, so coding agents
(Claude Code, Codex, Grok) can deploy and inspect apps as native tools instead
of shelling out:

```bash
claude mcp add cleat -- cleat mcp
codex  mcp add cleat -- cleat mcp
grok   mcp add cleat -- cleat mcp
```

Tools: `whoami`, `servers_list`, `apps_list`, `apps_show`, `apps_create`,
`apps_update`, `apps_logs`, `env_list`, `env_set`, `env_unset`, `deploy`,
`deploy_status`, `deploy_logs`, `cancel_deploy`, `drop`, `init_project`.

`deploy` queues and returns a `deployment_id`; follow it with `deploy_status`
and `deploy_logs`. Credentials come from `cleat login` (or `CLEAT_PANEL_URL` /
`CLEAT_TOKEN`).

### Project manifest

`cleat init` writes `.cleat_deploy/deploy.json`, the same manifest the panel
reads to decide how to build an app:

```json
{
  "runtime": "phoenix",
  "release_name": "my_app",
  "memory_max_mb": 400
}
```

For Go projects it detects binaries under `cmd/*/main.go`:

```json
{
  "runtime": "golang",
  "binaries": ["server", "worker"]
}
```

For static sites, `cleat init` detects the absence of `mix.exs`/`go.mod` plus an
`index.html` or `package.json`, or you can force it with `cleat init --runtime static`:

```json
{
  "runtime": "static"
}
```

The panel optionally runs `npm ci && npm run build` and serves the output
directory (`dist`, `build`, `public`, `_site`, `out`, or `build_dir`) through
Caddy with an SPA fallback — no runtime process. Plain HTML/CSS/JS folders with
an `index.html` at the repo root are published as-is, no build step.

For server-rendered JS (Next.js, TanStack Start), `cleat init` detects `next` or
a `@tanstack/*-start` dependency and picks the `node` runtime. The panel installs
Node, runs `npm ci && npm run build`, and keeps the app alive with a systemd unit
behind Caddy (`reverse_proxy`). devDependencies are pruned after the build
(`npm prune --omit=dev`), and TanStack Start / Nitro releases ship no
`node_modules` at all since the `.output` bundle is self-contained. The start
command is resolved at build time:

1. `start_command`, if set in the manifest
2. `npm run start`, if the project declares a `start` script
3. `node .output/server/index.mjs` for TanStack Start / Nitro output
4. `npm exec -- next start` for Next.js output

```json
{
  "runtime": "node",
  "build_command": "npm run build",
  "start_command": "npm start",
  "node_version": "22"
}
```

Only `runtime` is required; `build_command`, `start_command`, and `node_version`
(uses the latest 22.x when omitted) are optional overrides. Point `build_dir` at
a subdirectory for monorepos (`{"runtime": "node", "build_dir": "web"}`).

For Ruby on Rails, `cleat init` detects a `Gemfile` plus `config/application.rb`
(or a `rails` gem) and picks the `rails` runtime. The panel installs Ruby via
mise, runs `bundle install`, `assets:precompile` and `db:prepare`, then serves
the app with Puma behind Caddy. `DATABASE_URL`, `SECRET_KEY_BASE` and
`RAILS_MASTER_KEY` come from the panel env vars.

```json
{
  "runtime": "rails",
  "ruby_version": "3.3.6",
  "start_command": "bundle exec puma -C config/puma.rb"
}
```

Ruby version resolution order: `ruby_version` → `.ruby-version` → the Gemfile
`ruby` directive → 3.3.6. Start command: `start_command` → `bundle exec puma -C
config/puma.rb` → `bundle exec puma -b tcp://0.0.0.0:$PORT`.

Commit the manifest so the panel picks it up on the next deploy.

### Logs

`apps logs` reads an app's systemd journal; `servers logs` reads the host
journal (all units, or one with `--unit`):

```bash
cleat apps logs lumina --tail 500 --since 1h --grep error
cleat servers logs 5 --unit caddy --since 30m
```

`--since` accepts `30m`, `2h`, `1d` or an ISO date (`2026-09-21`,
`2026-09-21 14:30`). `--grep` is a case-sensitive substring filter. `--tail`
defaults to 200 (max 5000). `--follow` keeps polling and prints new lines.

### Environment variables

Env vars are stored encrypted by the panel and written to the server
(`/etc/<app>/env`) during a deploy. They are masked by default:

```bash
cleat env list my-app              # secrets shown as •••
cleat env list my-app --reveal     # show values in the clear

cleat env set my-app DATABASE_URL=libsql://... SECRET_KEY_BASE=...
cleat env set my-app FOO=bar --deploy   # apply immediately (one deploy)

cleat env unset my-app OLD_KEY --deploy
```

Keys must be `UPPER_SNAKE_CASE`. A value with `=` (`KEY=a=b`) is supported.
Without `--deploy`, run `cleat deploy APP` to apply the changes.

### Deploying a repo

Deploy an app that is already registered:

```bash
cleat deploy my-app --watch
cleat deploy my-app --ref deploy-cleat        # override the branch
```

Register and deploy in one shot. If the repo is unknown, pass `--server` and
`--host`; the app is created with sane defaults (slug from the repo name). The
runtime is detected from the local project the same way `cleat init` does, so a
Next.js / TanStack Start repo registers as `node`; override it with `--runtime`
(`phoenix`, `golang`, `node`, `rails` or `static`):

```bash
cleat deploy --repo owner/repo --server 3 --host repo.example.com --watch
cleat deploy --repo owner/lumina --server 3 --subdomain lumina --runtime node
```

Edit an existing app (including its runtime) and cancel a stuck deploy:

```bash
cleat apps update my-app --branch develop --no-auto-deploy
cleat apps update my-app --runtime node
cleat cancel my-app
```

### Drop (no git)

`cleat drop` packages a local folder or a single file and publishes it as a
static site — no repository needed. It works exactly like Netlify Drop:

```bash
# against an existing static app
cleat drop ./dist --app landing --watch

# create the static app on the fly (server required; host optional for plain static)
cleat drop ./site --server 3 --host landing.example.com --watch

# a single file: uploaded as index.html (or its own name when not HTML)
cleat drop ./almanaque.html --server 3 --host almanaque.example.com --watch
```

Plain static sites get a host automatically. When the target is a single
`.html`/`.htm` file, or a directory with an `index.html` and no build manifest
(`package.json`, `mix.exs`, `go.mod`), you can publish without `--host`:

```bash
cleat config set sites_base_domain sites.example.com   # once

cleat drop ./minha-loja --server 3 --watch
# → minha-loja.sites.example.com

cleat deploy --repo owner/minha-loja --server 3        # same detection
```

Re-running a drop against the same slug updates the existing static app instead
of creating a new one. Pass `--host`/`--subdomain` to override, or
`--sites-base-domain` for a one-off. A non-static target without a host still
asks for one.

`.git`, `node_modules` and `.DS_Store` are excluded from the upload. The panel
enforces a size limit (default 50 MB, `CLEAT_DROP_MAX_BYTES` to override) and
only accepts drops for apps with `runtime: "static"`.

## Configuration

Resolution order for both the panel URL and the token:

1. `--panel` / `--token` flags
2. `CLEAT_PANEL_URL` / `CLEAT_TOKEN` environment variables
3. `~/.config/cleat/config.json` written by `cleat login`

Set `CLEAT_CONFIG` to use a different config file path.
Add `--json` to any read command for machine-readable output.

### Named subdomains

Create one DNS wildcard (`*.sites.example.com` → your server) and let the CLI
build the host for you. Set the base domain once:

```bash
cleat config set base_domain sites.example.com
```

Then `--subdomain` expands to `<name>.<base_domain>`:

```bash
cleat drop ./site --server 3 --subdomain exemplo --watch
# → exemplo.sites.example.com

cleat deploy --repo owner/repo --server 3 --subdomain exemplo --runtime static --watch
```

`--base-domain` overrides the stored value per command, and `CLEAT_BASE_DOMAIN`
sets it via the environment. Use `--host` for a full domain. The panel issues a
Let's Encrypt certificate per host automatically; it does not need to know the
base domain.

For static sites, set `sites_base_domain` to give plain static drops and deploys
a base domain when they omit `--host`:

```bash
cleat config set sites_base_domain sites.example.com
```

Override it per command with `--sites-base-domain`, or via
`CLEAT_SITES_BASE_DOMAIN`.

## Development

```bash
mix test
mix precommit
```

## License

MIT
