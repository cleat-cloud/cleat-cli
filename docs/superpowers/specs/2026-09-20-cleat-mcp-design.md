# cleat mcp — MCP server embutido no CLI

Data: 2026-09-20
Status: aprovado (design) — pronto para plano de implementação

## Problema

O `cleat` já faz deploy, status, logs e env pela API do painel, mas só por
comandos de shell. Agentes (Claude Code, Codex, Grok) conseguem rodar shell, o
que torna o fluxo frágil: o agente precisa saber o subcomando exato, parsear
saída de tabela e lidar com flags. Não há uma interface estável e com schema
para "faça o deploy".

## Objetivo

Expor o Cleat como um servidor **MCP (Model Context Protocol)** para que o
agente chame tools nativas com schema, sem depender de shell. Registrar uma vez
em cada agente e o agente passa a saber o que o Cleat faz:

```bash
claude mcp add cleat -- cleat mcp
codex  mcp add cleat -- cleat mcp
grok   mcp add cleat -- cleat mcp
```

## Decisões (do brainstorming)

- **MCP embutido no próprio `cleat`**, via subcomando `cleat mcp`. Sem projeto
  separado.
- **Transporte stdio** puro. O agente sobe o processo quando precisa; sem porta
  ou processo residente.
- **Superfície completa** de tools (não só deploy).
- **Auth reusa** `~/.config/cleat/config.json` (do `cleat login`), com override
  por `CLEAT_PANEL_URL` / `CLEAT_TOKEN`.
- **Deploy assíncrono**: `deploy` retorna `deployment_id`; o agente acompanha com
  `deploy_status` / `deploy_logs`.
- **Distribuição**: escript via `mix install` (como hoje). Sem auto-registro.
- **Sem dependência de MCP**: implementar o framing à mão dentro de
  `Cleat.MCP.*`. `anubis_mcp` traz Phoenix/Finch/Plug e é LGPL — peso e licença
  desnecessários para um MCP stdio local num escript.

## Arquitetura

```
cleat mcp
  └─ Cleat.MCP.Server      loop stdio (lê stdin, escreve stdout)
       ├─ Cleat.MCP.Protocol  parse/serialize JSON-RPC 2.0 (newline-delimited)
       ├─ Cleat.MCP.Tools     registry declarativo: tool -> schema + handler
       └─ client existente    Cleat.Client / Cleat.Commands / Cleat.Config
```

- `stdout` é **exclusivo** do protocolo. Diagnóstico vai para `stderr`.
- Cada linha de stdin é um objeto JSON-RPC; cada resposta/notificação é uma
  linha de stdout. Não há `Content-Length` no transporte stdio do MCP.
- O servidor roda até EOF do stdin (o agente fecha o processo).

### Componentes

**`Cleat.MCP.Protocol`**
- Serializa/desserializa mensagens JSON-RPC 2.0 com `Jason`.
- Valida `jsonrpc: "2.0"`, `id`, `method`, `params`.
- Monta `result`, `error` (code/message) e resposta de tool (`content`, `isError`).
- Códigos de erro: `-32700` parse, `-32600` invalid request, `-32601` method not
  found, `-32602` invalid params, `-32603` internal.

**`Cleat.MCP.Server`**
- `run/1`: loop de leitura. Métodos tratados:
  - `initialize` → capabilities `{tools: %{}}`, `serverInfo` (name `cleat`,
    version do projeto), `protocolVersion` negociado.
  - `notifications/initialized` → no-op.
  - `tools/list` → lista do registry.
  - `tools/call` → despacha para o handler da tool.
  - `ping` → `{}`.
  - método desconhecido → erro `-32601`.
- Erros de handler viram `tools/call` com `isError: true` e mensagem legível; o
  processo nunca morre por causa de uma tool.

**`Cleat.MCP.Tools`**
- Um registry estático (lista de maps) com: `name`, `description`, `inputSchema`
  (JSON Schema), `handler` (função que recebe o map de args e devolve
  `{:ok, text}` ou `{:error, message}`).
- Os handlers reusam `Cleat.Client` e a lógica existente em `Cleat.Commands` /
  `Cleat.Config`, sem duplicar regra de negócio.
- Toda tool aceita opcionais `panel` e `token` para override (repassados a
  `Cleat.Commands.client/1`).

### Tools

| Tool | Args | Descrição |
|------|------|-----------|
| `whoami` | — | Usuário e tenant autenticados |
| `servers_list` | — | Lista servidores |
| `apps_list` | — | Lista apps |
| `apps_show` | `app` | Detalhe de um app (id ou slug) |
| `apps_create` | `name`, `repo`, `host`, `server`, `runtime?`, `slug?`, `branch?`, `port?` | Cria app |
| `apps_update` | `app`, `branch?`, `host?`, `port?`, `repo?`, `runtime?`, `auto_deploy?` | Edita app |
| `apps_logs` | `app` | Logs de runtime (systemd) |
| `env_list` | `app`, `reveal?` | Lista env vars |
| `env_set` | `app`, `vars` (map) | Upsert de env vars |
| `env_unset` | `app`, `key` | Remove uma env var |
| `deploy` | `app`, `ref?` | Dispara deploy; retorna `deployment_id` |
| `deploy_status` | `app` | Deployments recentes |
| `deploy_logs` | `id` | Log de build de um deployment |
| `cancel_deploy` | `app` | Cancela o deploy ativo |
| `drop` | `path`, `app?`, `server?`, `host?`, `slug?`, `ref?` | Publica pasta/arquivo estático (sem git) |
| `init_project` | `runtime?` + overrides | Escreve `.cleat_deploy/deploy.json` no cwd |

Notas:
- As respostas são **JSON compacto** (`Output.json`) dentro de `content` textual;
  o agente lê o JSON. Isso evita inventar tipos MCP e mantém o contrato estável.
- `deploy` só dispara; `deploy_status`/`deploy_logs` acompanham.

## Tratamento de erros

- Falha de rede/HTTP: mensagem clara (`404 Not found`, `401 Unauthorized`) com a
  ação sugerida (ex.: "run `cleat login`"), como `isError: true`.
- Config ausente (`~/.config/cleat/config.json` sem `panel_url`): erro explícito
  dizendo para rodar `cleat login` ou setar `CLEAT_PANEL_URL`/`CLEAT_TOKEN`.
- Args inválidos: erro de validação citando os campos faltantes/ inválidos.
- Nenhum erro derruba o loop.

## Testes

- `Cleat.MCP.ProtocolTest`: encode/decode de request/response/erro, linha
  inválida, `id` ausente (notificação).
- `Cleat.MCP.ServerTest`: `initialize`, `tools/list`, `tools/call` (com
  `Req.Test`), `ping`, método desconhecido, tool com erro do painel.
- `Cleat.MCP.ToolsTest`: cada tool monta a chamada certa na API (path/método/
  body), usando `Req.Test`; validação de args obrigatórios.
- E2E leve: alimenta stdin com `initialize` + `tools/list` e valida as linhas de
  stdout (protocolo puro, sem rede).
- `mix precommit` verde (compile sem warnings, format, testes).

## Fora de escopo

- Transporte HTTP/SSE residente.
- Auto-registro do MCP em `claude`/`codex`/`grok` (o usuário registra uma vez).
- MCP resources e prompts (só tools).
- Streaming incremental do log de build como notificação MCP (o agente faz poll
  em `deploy_logs`).

## Critério de sucesso

1. `cleat mcp` responde `initialize`, `tools/list` e `tools/call` corretamente
   em stdio.
2. Registrado em `claude mcp add cleat -- cleat mcp`, o agente consegue listar
   apps e disparar um deploy sem shell manual.
3. Nenhuma dependência nova de runtime; escript continua um binário único.
