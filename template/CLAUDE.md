# CLAUDE.md

## O que é

{= display_name =}: {= description =}

Gerado pelo `scaffold-flutter-rust` (`/Volumes/Projects/scaffold-flutter-rust`), no desenho do
bulkscan: backend Rust (`server/`, axum + SeaORM sobre Postgres), frontend Flutter (`app/`: build
web e app Android do mesmo código). Emails pelo jmail (`/Volumes/Projects/jmail`).

Prosa (comentários, mensagens de erro da API, textos de UI) em português acentuado;
identificadores em inglês.

## Regra: backend sempre com hot-patch

É imperativo: para rodar, testar ou iterar no backend, o Claude Code usa `./hot.sh` (em background,
com `--interactive false` quando não há TTY), nunca `cargo run` reiniciado a cada mudança. Suba uma
vez, edite e confira pelo log do dx (`Hot-patching: ... took NNNms`) e pela própria API, sem
reiniciar o processo. Rebuild completo só quando o patch não serve: mudou struct, enum ou
assinatura de função, `Cargo.toml` ou o `setup` frio; aí `r` no dx (ou reinicia o `./hot.sh`). Se o
patch falhar ou o processo cair depois dele, investigue e conserte a causa (ver a seção
Hot-patch do backend) em vez de voltar para o `cargo run`.

## Comandos

```bash
docker-compose up -d db                                   # Postgres (colima: use docker-compose)
docker exec -i {= name =}-pg psql -U {= name =} -d {= name =} < server/schema.sql   # schema, 1ª vez
cp server/.env.example server/.env                        # JWT_SECRET e JMAIL_API_KEY obrigatórios
cd server && cargo run                                    # API em :8080 (serve app/build/web se existir)
./hot.sh                                                  # a mesma API com hot-patch do Rust (dx serve)
cd app && flutter build web --release                     # web
cd app && flutter build apk --release -PdiscordClientId=<id>   # Android
docker-compose up --build                                 # tudo: API :8080, web :8081
```

O compose não monta o `schema.sql` no initdb porque o colima não enxerga `/Volumes`.
`python3 app/tool/icones.py` regenera os ícones a partir de `app/web/favicon.svg`.

## Hot-patch do backend

`./hot.sh` roda a API pelo `dx serve --hot-patch --features hot` (dioxus-cli 0.7.10, chamado por
`~/.cargo/bin/dx` porque o `dx` do Deno vem antes no PATH; o devserver do dx vai para a 8090).
Salvar o corpo de uma função em `server/src` aplica no processo rodando em ~1 s: `main.rs` separa o
`setup` frio (env, log, banco, email, faxina) do `serve` quente (roteador + HTTP), que é recriado a
cada patch. Mudou struct, enum ou assinatura: `r` no terminal do dx (rebuild completo). Nada de
`std::env::var` na parte quente. Não ponha `[profile.dev.package."*"] opt-level = 3` no
`Cargo.toml`: com ele o patch aplica e o processo cai com "no reactor running".

## Arquitetura

- Auth (igual à do bulkscan): magic link (`auth.rs`), Google e Discord (`oauth.rs`, fluxo de código
  no servidor com prova PKCE do app; no Android o Discord autoriza no app dele e volta por
  `discord-{id}:/authorize/callback`), código de acesso para a revisão da Play Store. JWT de 15 min +
  refresh opaco rotativo. Contas em SQL direto pelo sqlx no mesmo pool do SeaORM.
- Domínio no SeaORM: `server/src/entities/` e `server/src/routes/`, um submódulo por recurso
  ({% for e in entities %}`{= e.plural =}`{% if not loop.last %}, {% endif %}{% endfor %}), handlers com
  `State<DatabaseConnection>` + extractor `Auth`, sempre filtrando pelo dono. Schema em
  `server/schema.sql`; sem migrations automáticas: mudança vai no schema e num script idempotente
  em `db/migrations/`.
- Erros da API: `{"error": "..."}` via `ApiError`; 5xx sem detalhe do banco.
- App: `main.dart` (go_router; `/login`, `/entrar`, `/authorize/callback` fora do shell; as telas
  das entidades e `/conta` dentro do `ResponsiveScaffold`: rail lateral ≥ 800 px, barra inferior
  abaixo). `api/client.dart` é o único acesso à API; `models/` espelha os DTOs. `platform/` isola o
  que é só web/Android (não importar `package:web` fora dali). Base visual em `widgets/`
  (`PageScaffold`, `ApiState`, `InlineNotice`, diálogos); erro inline, nunca toast.
- Produção: nginx do `app` faz proxy de `/api/` para `{= env_prefix =}_API_HOST`; domínio
  `{= domain =}` (em `api/client.dart`, no manifest Android e no `assetlinks.json`, a criar).
