# cleat-cli

`cleat` is the command-line client for [Cleat](https://github.com/puppe1990/cleat-deploy),
a control panel that deploys Phoenix/Elixir and Go apps to Hetzner Cloud and AWS
Lightsail over SSH.

It talks to the panel's JSON API (`/api/v1`) to list servers and apps, trigger
deploys, and watch build logs.

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
| `cleat servers list` | List servers |
| `cleat servers show ID` | Show one server |
| `cleat apps list` | List apps |
| `cleat apps show APP` | Show one app (by id or slug) |
| `cleat apps create` | Create an app |
| `cleat apps update APP` | Edit branch / auto-deploy |
| `cleat env list APP` | List env vars (secrets masked) |
| `cleat env set APP K=V` | Upsert one or more env vars |
| `cleat env unset APP KEY` | Delete an env var |
| `cleat deploy APP` | Trigger a deploy (by id or slug) |
| `cleat deploy --repo O/R` | Register if needed, then deploy |
| `cleat cancel APP` | Cancel the active deploy |
| `cleat status APP` | List recent deployments for an app |
| `cleat logs DEPLOYMENT_ID` | Print a deployment's build log |

Run `cleat help` for the full option list.

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

Commit the manifest so the panel picks it up on the next deploy.

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
`--host`; the app is created with sane defaults (slug from the repo name):

```bash
cleat deploy --repo owner/repo --server 3 --host repo.example.com --watch
```

Edit an existing app and cancel a stuck deploy:

```bash
cleat apps update my-app --branch develop --no-auto-deploy
cleat cancel my-app
```

## Configuration

Resolution order for both the panel URL and the token:

1. `--panel` / `--token` flags
2. `CLEAT_PANEL_URL` / `CLEAT_TOKEN` environment variables
3. `~/.config/cleat/config.json` written by `cleat login`

Set `CLEAT_CONFIG` to use a different config file path.
Add `--json` to any read command for machine-readable output.

## Development

```bash
mix test
mix precommit
```

## License

MIT
