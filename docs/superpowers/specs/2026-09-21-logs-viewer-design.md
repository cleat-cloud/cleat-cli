# Log viewer (app + host) — design

Data: 2026-09-21
Status: aprovado (design) — pronto para plano de implementação

## Problema

O Cleat só mostra o journal do app (`cleat apps logs APP`), fixo em 200 linhas,
sem filtro. Não há como ver:

- os logs do **host** (caddy, sshd, systemd, OOM) por servidor;
- um período, um tail maior, ou só as linhas que casam com um texto.

## Objetivo

`apps logs` com filtros (`--tail`, `--since`, `--grep`, `--follow`) e um novo
`servers logs` para o journal do host, no CLI e no MCP. Também melhorar
`apps logs` no CLI e adicionar `server_logs` no MCP.

## Decisões (do brainstorming)

- **journalctl, sem `dmesg`.** "Logs do sistema" = journal do host (todos os
  units de uma vez). O log de kernel fica fora de escopo.
- **Acesso por servidor** (`cleat servers logs ID`): quem tem acesso ao tenant vê
  o journal do host.
- **Filtros**: `--tail N` (default 200), `--since` (ISO ou relativo `30m`/`2h`/`1d`),
  `--grep TEXT`, `--unit NAME`, `--follow` (CLI, polling).
- **`grep` é substring**, filtrado no painel (não regex no servidor): previsível
  e sem risco de ReDoS.
- **Validação no painel** (fonte da verdade): `unit` por allowlist de caracteres,
  `since` por padrão, `tail` por faixa. O CLI também valida para dar erro cedo.
- **MCP**: `apps_logs` ganha `tail`/`since`/`grep`; nova tool `server_logs`
  (`server`, `unit?`, `tail?`, `since?`, `grep?`). Sem `follow` no MCP.

## Arquitetura

**Painel (`cleat-web`)**

- `CleatDeploy.Logs` (renomeia/expande `CleatDeploy.Apps.RuntimeLogs`):
  - `fetch_app(app, opts)` → journal do unit do app;
  - `fetch_server(server, opts)` → journal do host (`unit` opcional);
  - opts: `unit`, `since`, `tail`, `grep`.
  - Monta o argv do `journalctl` como lista (nunca shell). `--no-pager -o
    short-iso --utc` sempre; `-n <tail>`; `--since <since>` quando dado;
    `-u <unit>` quando dado.
  - `grep` não vai pro journalctl: filtra as linhas depois (`String.contains?`).
- `CleatDeploy.Logs.Args` (ou funções no módulo) com a validação:
  - `unit`: `^[A-Za-z0-9:_.@-]+$` (mesmo padrão de hoje), tamanho ≤ 128;
  - `since`: ISO (`YYYY-MM-DD` ou `YYYY-MM-DD HH:MM[:SS]`) ou duração
    `^\d+(s|m|h|d|w)$`; tamanho ≤ 32;
  - `tail`: inteiro 1..5000 (default 200);
  - `grep`: string ≤ 200 chars (sem validação de regex, é substring);
  - qualquer falha → `{:error, {:invalid, campo}}` → API responde 422.
- Rotas:
  - `GET /api/v1/apps/:app_id/logs?tail&since&grep` (sem `unit`: usa o do app);
  - `GET /api/v1/servers/:id/logs?unit&tail&since&grep` (sem `unit`: host inteiro).
- Resposta: `%{unit, lines, fetched_at}` (app) e `%{unit|nil, lines, fetched_at}`
  (server). Erros 422 para filtros inválidos, 502 para falha de SSH/journalctl.

**CLI (`cleat-cli`)**

- `cleat apps logs APP [--tail N] [--since S] [--grep T] [--follow]` → path +
  querystring.
- `cleat servers logs ID [--unit U] [--tail N] [--since S] [--grep T] [--follow]`
  → novo; sem `--unit`, host.
- `--follow` segue sendo polling (re-consulta e imprime o delta), reusando o
  `Output.log_delta/2` que já existe.
- Ajuda (`cli.ex`) e README atualizados.

**MCP (`cleat-cli`)**

- `apps_logs`: adiciona `tail`, `since`, `grep` ao schema e à chamada.
- `server_logs`: `{ server, unit?, tail?, since?, grep? }` → `Client.server_logs/3`.
- `Cleat.Client` ganha `server_logs(client, id, opts)` e `app_logs/3` (com opts).

## Erros

- Filtro inválido → o painel responde 422 com a mensagem do campo; o CLI/MCP
  repassa. Mensagens: `invalid since (use 30m, 2h, 1d or 2026-09-21)`,
  `invalid unit`, `tail must be between 1 and 5000`.
- Servidor sem SSH/key → 502, como hoje.

## Fora de escopo

- `dmesg` / journal do kernel (`-k`).
- `--level`/priority.
- Streaming de verdade (SSE/websocket); `--follow` continua polling.
- Logs de outros tenants.

## Critério de sucesso

1. `cleat servers logs 5 --since 1h --grep error` mostra as linhas do host que
   casam, do último período.
2. `cleat apps logs lumina --tail 500 --follow` funciona como hoje, com filtros.
3. MCP: `server_logs` e `apps_logs` retornam as mesmas linhas com os filtros.
4. `unit`/`since` inválidos dão erro claro, sem executar comando no servidor.
