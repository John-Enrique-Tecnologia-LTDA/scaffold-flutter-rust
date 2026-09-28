---
name: scaffold-flutter-rust
description: Gerar um projeto novo completo Flutter (web + Android) + Rust (axum + SeaORM + Postgres) com login sem senha (magic link, Google, Discord), CRUD por entidade, layout responsivo, Docker e hot-patch do backend, a partir de um manifest TOML, usando o CLI `scaffold`. Use quando pedirem para criar/iniciar/scaffoldar um app, projeto, SaaS ou sistema novo com Flutter e Rust, "igual ao bulkscan/jopendaw", "faz o scaffold", "cria o projeto com auth e CRUD", ou para escrever/validar um manifest do scaffold. Também explica como trabalhar no projeto gerado (subir banco, rodar com hot-patch, adicionar entidades depois).
---

# scaffold-flutter-rust

CLI que gera, numa pasta nova, um projeto pronto para rodar: backend Rust (axum + SeaORM sobre
Postgres), app Flutter com build web (PWA) e Android do mesmo código, autenticação sem senha e um
CRUD completo para cada entidade declarada no manifest. Repositório:
https://github.com/John-Enrique-Tecnologia-LTDA/scaffold-flutter-rust

Binário instalado com esta skill: `{{SCAFFOLD_BIN}}`. Se não existir mais, procure `scaffold` no
PATH ou clone o repositório e use `./scaffold` (binário por plataforma em `bin/`, o `./scaffold` da
raiz escolhe o certo) ou `./build.sh` para compilar.

## Fluxo (siga nesta ordem)

1. **Entenda o domínio** com quem pediu: nome do app, para que serve, quais "coisas" ele guarda
   (entidades) e os campos de cada uma. Não invente entidades que não foram pedidas; se o pedido
   é vago, proponha 1 a 3 entidades e confirme.
2. **Escreva o manifest** (formato abaixo). Parta do exemplo: `scaffold example > app.toml`.
3. **Valide**: `scaffold check app.toml`. Corrija até passar (as mensagens dizem o campo e o motivo).
4. **Gere**: `scaffold new app.toml <pasta>`. A pasta **não pode existir** (o CLI recusa e não
   sobrescreve nada). Ele escreve os arquivos e depois roda: ícones (Chrome headless),
   `flutter pub get`, `dart format`, `cargo fmt`, `git init`. Passo que falha só avisa.
   `--no-post` pula esses passos.
5. **Confira** (não pule): `cd <pasta>/server && cargo clippy` e `cd <pasta>/app && flutter analyze`,
   ambos devem sair limpos.
6. **Suba e teste** seguindo o `CLAUDE.md` gerado (resumo em "Depois de gerar").

## Manifest (TOML), referência completa

```toml
name = "tarefas"                    # obrigatório: [a-z][a-z0-9]*, até 30; sem hífen nem _
display_name = "Tarefas"            # obrigatório: nome mostrado (título, login, ícone, emails)
description = "Suas tarefas..."     # obrigatório: meta description, manifest do PWA, pubspec
tagline = "Tudo o que falta..."     # opcional (padrão: description): frase do login
org = "tech.johnenrique"            # obrigatório: domínio invertido; pacote Android = org.name
domain = "tarefas.johnenrique.tech" # obrigatório: host de produção

[colors]
accent = "#35D0C0"                  # obrigatório, #RRGGBB
# opcionais (derivados de accent se omitidos):
# accent_dark, accent_light (degradê da logo), on_accent (letra da logo), glow (brilho do login)

[[entities]]                        # pelo menos uma; a PRIMEIRA é a tela inicial (rota /)
name = "task"                       # snake_case singular
plural = "tasks"                    # opcional (padrão name + "s"); vira tabela e /api/<plural>
label = "Tarefa"                    # rótulos em português, como aparecem na tela
label_plural = "Tarefas"
gender = "f"                        # "m" (padrão) ou "f": "Nova tarefa", "Nenhuma tarefa ainda"
icon = "task_alt"                   # nome de um Icons.* do Material (padrão "folder")

  [[entities.fields]]               # pelo menos um; o PRIMEIRO do tipo string é o título
  name = "title"                    # snake_case
  type = "string"                   # string | text | int | float | bool
  label = "Título"
  max = 200                         # string/text: máx. de caracteres; int/float: valor máximo
  # required = true                 # só string/text; o título é sempre obrigatório
  # min = 0                         # só int/float
  # default = 3                     # do tipo do campo; dentro de min/max
```

Tipos: `string` (uma linha, sem quebra), `text` (várias linhas), `int` (i32 / int / INTEGER),
`float` (f64 / double / DOUBLE PRECISION), `bool`. Todo campo é `NOT NULL` com default (texto `''`,
número 0 ou `min` se positivo, bool `false`), então dá para adicionar campo sem migração complicada.

### Regras de validação (o `check` recusa)

- `name` do app só com minúsculas e dígitos; nomes de entidade/campo em snake_case sem `__` e sem
  terminar em `_`.
- Entidade cujo nome em PascalCase colide com classe do Dart/Flutter/template: `list`, `map`, `set`,
  `string`, `object`, `type`, `future`, `stream`, `error`, `user`, `session`, `model`, `entity`,
  `card`, `form`, `page`, `icon`, `text`, `color`, `theme`, `state`, `widget`, `router`, `path`,
  `auth`, `account`, `link`, `login`, `table`, `row`, `dialog`, `chip`, `badge`, `banner`… Use um nome
  composto (`shopping_list`, `task_group`).
- Campo com nome reservado: `id`, `owner_id`, `created_at`, `updated_at` (já existem em toda
  tabela) e palavras-chave de Dart/Rust (`type`, `class`, `default`, `new`, `in`, `fn`, `mod`, `self`,
  `match`, `async`, `state`, `item`, `widget`, `context`…).
- Textos (`display_name`, `description`, `tagline`, labels, defaults de texto) sem aspas, `\`, `$`,
  chaves, `<`, `>` nem crase: eles entram direto em código Dart/Rust/HTML/JSON.
- Entidade sem campo `string`; campos ou entidades repetidos; plural igual a outro nome;
  `min > max`; default fora de min/max; `min`/`required` em tipo que não aceita; cores fora de
  `#RRGGBB`.

## O que é gerado

```
<pasta>/
  Cargo.toml, Cargo.lock, rust-toolchain.toml (stable), rustfmt.toml   workspace Rust
  hot.sh                     backend com hot-patch (dx serve); ver "Regra do hot-patch"
  docker-compose.yml         db (Postgres 17), api (:8080), web (:8081)
  CLAUDE.md                  guia do projeto para agentes (comandos, arquitetura, regras)
  server/
    schema.sql               contas + uma tabela por entidade (owner_id, created_at, updated_at)
    .env.example             variáveis (JWT_SECRET e JMAIL_API_KEY obrigatórias)
    Dockerfile               build no contexto da raiz: docker build -f server/Dockerfile .
    src/main.rs              setup frio + serve quente (hot-patch); feature `hot`
    src/auth.rs, oauth.rs    magic link, Google, Discord, refresh rotativo, código de revisão
    src/entities/<e>.rs      entidade SeaORM por entidade do manifest
    src/routes/<plural>.rs   CRUD /api/<plural> (list, get, create, patch, delete), só do dono,
                             validação por campo (check_<campo>) com erro {"error": "..."}
  app/
    lib/main.dart            go_router: /login, /entrar, /authorize/callback e o shell
    lib/api/client.dart      único acesso à API (JWT + renovação no 401), métodos por entidade
    lib/models/<e>.dart      DTO por entidade
    lib/screens/<e>_screen.dart  grade responsiva + formulário (diálogo no desktop, folha no celular)
    lib/widgets/             tema (cor do manifest), PageScaffold, ResponsiveScaffold (rail ≥ 800 px,
                             barra inferior abaixo), avisos inline, diálogos
    web/                     index.html, PWA (manifest, sw.js), páginas legais (rascunho), ícones
    android/                 pacote org.name, retorno do OAuth, links do email, assinatura release
    nginx.conf.template, Dockerfile   imagem web com proxy de /api para <NAME>_API_HOST
    tool/icones.py           regenera ícones a partir de web/favicon.svg (Chrome headless)
```

Nomes derivados: crate `<name>-server`, pacote Dart `<name>_app`, banco/usuário/senha locais
`<name>`, container `<name>-pg`, variáveis do nginx `<NAME>_...`, pacote Android `<org>.<name>`,
chaves de armazenamento `<name>.access`/`<name>.refresh`.

## Depois de gerar

```bash
cd <pasta>
docker-compose up -d db
docker exec -i <name>-pg psql -U <name> -d <name> < server/schema.sql   # 1ª vez
cp server/.env.example server/.env    # preencher JWT_SECRET (openssl rand -base64 48) e JMAIL_API_KEY
./hot.sh                              # API em :8080 com hot-patch (serve app/build/web se existir)
(cd app && flutter build web --release)                     # web servido pela própria API em dev
(cd app && flutter build apk --release -PdiscordClientId=<id>)
docker-compose up --build             # tudo em containers (API :8080, web :8081)
```

- Sem jmail/OAuth configurados dá para entrar pelo **código de acesso**: `REVIEW_EMAIL` e
  `REVIEW_CODE` (24+ caracteres) no `.env`, e "Tenho um código de acesso" no login.
- Google/Discord: `GOOGLE_CLIENT_ID/SECRET`, `DISCORD_CLIENT_ID/SECRET`; retornos registrados em
  `{APP_BASE_URL}/api/auth/oauth/<provedor>/callback` e, no Discord, também
  `discord-<id>:/authorize/callback`. Sem o par, o botão some.
- Produção: trocar o domínio se mudou, criar `app/web/.well-known/assetlinks.json` (links do email
  no Android), chave de release em `~/.config/<name>/android-release.properties`, revisar
  `privacidade.html` e `termos.html`.

## Regra do hot-patch (imperativa no projeto gerado)

Para rodar ou iterar no backend use `./hot.sh` (em background, `--interactive false` sem TTY),
nunca `cargo run` reiniciado a cada mudança. Edite, salve e confira `Hot-patching: ... took NNNms`
no log e a API respondendo, sem reiniciar. Rebuild completo (`r` no dx ou reiniciar) só quando mudou
struct/enum/assinatura, `Cargo.toml` ou o `setup` frio. Detalhes verificados:
- Precisa do dioxus-cli 0.7.x (`cargo install dioxus-cli --version 0.7.10 --locked`). O `hot.sh`
  chama `~/.cargo/bin/dx` (o `dx` do Deno no Homebrew costuma vir antes no PATH; `DX=` sobrescreve).
- O devserver do dx vai para a 8090 (`DX_PORT`), porque a API usa a 8080.
- Não coloque `[profile.dev.package."*"] opt-level = 3`: o patch aplica e o processo cai com
  "no reactor running".
- Nada de `std::env::var` na parte quente (`serve`): o `.env` é lido no `setup`.

## Evoluir o projeto gerado (sem o CLI)

O CLI só cria projetos novos. Para **adicionar uma entidade** depois, copie o padrão das existentes:
1. `server/schema.sql`: nova tabela (mesmo formato) + script idempotente em `db/migrations/`
   (`CREATE TABLE IF NOT EXISTS ...`) para rodar à mão onde o banco já existe.
2. `server/src/entities/<e>.rs` e o `pub mod` + `prelude` em `entities/mod.rs`.
3. `server/src/routes/<plural>.rs` e as duas `.route(...)` + `mod` em `routes/mod.rs`.
4. `app/lib/models/<e>.dart`, métodos em `api/client.dart`, `screens/<e>_screen.dart`, rota em
   `main.dart` e destino em `widgets/responsive_scaffold.dart`.
Alternativa rápida: gere um projeto descartável com a entidade no manifest (`--no-post`) numa pasta
temporária e copie os arquivos dela, trocando os nomes.

Para **adicionar campo**: coluna no `schema.sql` + migração `ALTER TABLE ... ADD COLUMN IF NOT
EXISTS ... NOT NULL DEFAULT ...`, campo no `Model` SeaORM, nas structs `New*`/`Patch*` com um
`check_<campo>`, no model Dart e no formulário/resumo da tela. Mudou struct: rebuild (`r`).

## Problemas conhecidos

- **colima não monta `/Volumes/...`** no Docker: por isso o schema é aplicado por `docker exec -i
  ... psql < server/schema.sql`, não por volume do initdb.
- **`docker compose` ausente com colima**: use `docker-compose`.
- **Ícones não gerados** (sem Chrome): `CHROME=/caminho/do/chrome python3 app/tool/icones.py`.
  Sem os PNGs do launcher o build Android falha.
- **Porta 5432 ocupada** por outro projeto gerado: pare o outro (`docker-compose stop db`).
- **Erro "já existe"**: o CLI nunca escreve em pasta existente; escolha outra ou apague a antiga
  (confirme com o usuário antes de apagar).

## Mexer no próprio scaffold

Template em `template/` (embutido no binário; sintaxe minijinja `{= x =}`, `{% %}`, `{# #}`; só
arquivos que usam essa sintaxe são renderizados; `__android_path__`, `__entity__`, `__plural__` nos
caminhos). Lógica do manifest em `cli/src/manifest.rs`. Depois de mudar: `./build.sh` (binários de
todas as plataformas) e valide gerando `examples/tarefas.toml` e rodando clippy + flutter analyze.
