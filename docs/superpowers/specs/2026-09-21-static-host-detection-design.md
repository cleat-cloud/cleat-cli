# Static host detection for drop/deploy — design

Data: 2026-09-21
Status: aprovado (design) — pronto para plano de implementação

## Problema

`cleat drop ./site` e `cleat deploy --repo owner/site` exigem `--server` e
`--host` para registrar o app. Quando o conteúdo é só HTML, o natural é publicar
em `<slug>.sites.gestaobem.com` sem o usuário informar host — o CLI já sabe que
é estático.

Hoje existe um único `base_domain` (`apps.gestaobem.com`). Sites estáticos vivem
em outro domínio (`sites.gestaobem.com`), então a escolha do host depende do tipo
de conteúdo.

## Objetivo

Quando faltar `--host`, detectar que o alvo é estático e derivar
`<slug>.<sites_base_domain>` sozinho, tanto no CLI (`drop`, `deploy --repo`)
quanto na tool MCP `drop`. Sem host e não-estático, manter o erro acionável.

## Decisões (do brainstorming)

- **Vale em `drop` e `deploy --repo`**, e também no MCP.
- **Dois domínios no config**: `base_domain` (apps com servidor) e o novo
  `sites_base_domain` (estáticos). Resolução do segundo: flag
  `--sites-base-domain` → env `CLEAT_SITES_BASE_DOMAIN` → config →
  fallback `base_domain`.
- **"Só HTML"** = arquivo `.html`/`.htm`, ou diretório com `index.html` na raiz
  **e** sem `package.json`, `mix.exs` ou `go.mod`.
- **Slug** vem do nome da pasta/arquivo (drop) ou do repo (deploy `--repo`).
- **App existente com o mesmo slug e runtime `static`** → publicar nele
  (atualizar), sem criar duplicado.
- **App existente com runtime diferente** → erro acionável.
- **Módulo** `Cleat.Static` (detector), curto e no padrão de `Cleat.Pack`/`Cleat.Runtime`.

## Arquitetura

- `Cleat.Static` — `detect?(path)` (arquivo ou diretório) e `site_slug(path)`
  (nome da pasta/arquivo normalizado). Sem IO além de leitura de arquivos.
- `Cleat.Config` — chave gravável `sites_base_domain`; `Cleat.Config.sites_base_domain/0`.
- `Cleat.Commands` — `sites_base_domain(opts)` (precedência acima) e
  `host/1` ganha um caminho: quando não há host/subdomain e o alvo é estático,
  deriva do `sites_base_domain`.
- `Cleat.Commands.Drop` — ao publicar sem `--app`, se for estático e sem host,
  deriva o host; reusa app existente pelo slug (mesmo runtime) ou publica nele.
- `Cleat.Commands.Deploy` (`--repo`) — mesma detecção quando faltar host.
- `Cleat.MCP.Tools` — a tool `drop` aceita sem `server`/`host` para estáticos,
  retornando o host derivado no JSON.

## Fluxo

1. Se `--host`/`--subdomain` foi passado, usar (como hoje).
2. Sem host: se o alvo é estático (`Cleat.Static.detect?`), host =
   `<slug>.<sites_base_domain>` e runtime `static`.
3. Sem host e não-estático: erro pedindo `--host` (comportamento atual).
4. Antes de registrar, buscar app com o mesmo slug:
   - existe e `runtime == "static"` → publicar nele;
   - existe e runtime diferente → erro acionável;
   - não existe → criar.

## Erros

- Estático, mas sem `sites_base_domain` nem fallback e sem `--host`:
  "no sites base domain configured. Run `cleat config set sites_base_domain
  sites.example.com`, set CLEAT_SITES_BASE_DOMAIN, or pass --host."
- App existente com runtime diferente:
  "app `<slug>` already exists with runtime <r>; pass --app or a different --slug."

## Fora de escopo

- Subdomínio aninhado (ex.: `a.b.sites...`).
- Detectar frameworks além da regra de arquivos acima.
- Mudanças no painel: o `drop` já registra runtime `static`.

## Critério de sucesso

1. `cleat drop ./minha-loja` (só HTML) publica em
   `minha-loja.sites.gestaobem.com` sem `--host`.
2. `cleat deploy --repo owner/site --server N` (repo só HTML) idem.
3. Não-estático sem host continua pedindo `--host`.
4. Rodar de novo atualiza o app existente, sem duplicar.
