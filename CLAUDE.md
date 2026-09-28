# scaffold-flutter-rust

Gera um projeto completo no desenho do bulkscan/jopendaw a partir de um manifest TOML:

- **backend** Rust (axum + SeaORM + Postgres), com autenticação sem senha: magic link (jmail),
  Google e Discord (inclusive pelo app do Discord no Android), JWT curto + refresh rotativo, código
  de acesso para a revisão da Play Store;
- **app** Flutter com build web (PWA, nginx com CSP, Dockerfile) e Android (pacote, esquemas de
  retorno do OAuth, links do email), layout responsivo (rail lateral ≥ 800 px, barra inferior abaixo);
- **CRUD por entidade**: para cada entidade do manifest, tabela no `schema.sql`, entidade SeaORM,
  rotas `/api/<plural>` (sempre do dono, com validação por campo), model Dart, tela com grade
  responsiva e formulário (diálogo no computador, folha no celular), destino na navegação;
- docker-compose, ícones gerados da logo (inicial + cor da marca), `CLAUDE.md` do projeto.

## Uso

```bash
./scaffold example > meu.toml          # manifest de exemplo comentado (examples/tarefas.toml)
./scaffold check meu.toml              # valida e mostra o que seria gerado
./scaffold new meu.toml ../meu-app     # gera; a pasta não pode existir
./scaffold new meu.toml ../meu-app --no-post   # só os arquivos
./scaffold skill install               # instala a skill nos agentes de IA (ver abaixo)
```

Binários pré-compilados em `bin/` para macOS (arm64, x64), Linux (x64, arm64; estáticos, musl) e
Windows (x64). O `./scaffold` (e o `scaffold.cmd` no Windows) escolhe o da plataforma; não precisa
de Rust para usar.

## Skill para agentes de IA

`skill/SKILL.md` ensina um agente a usar o scaffold de ponta a ponta: entender o domínio, escrever e
validar o manifest (referência completa e todas as regras), gerar, conferir, subir o projeto,
a regra do hot-patch, evoluir o projeto depois (entidade/campo novos) e os problemas conhecidos.

```bash
./scaffold skill install --dry-run     # mostra onde instalaria
./scaffold skill install               # instala
./scaffold skill uninstall             # remove de todos
./scaffold skill print                 # imprime o SKILL.md
```

Vai sempre para `~/.agents/skills/scaffold-flutter-rust` (lida por Codex, Cursor, Gemini CLI,
OpenCode, GitHub Copilot, Amp, Goose) e também para a pasta própria dos agentes detectados pela
pasta de configuração: Claude Code (`~/.claude/skills`), Windsurf, Kiro, Factory Droid, Qwen Code,
Roo Code, Cline e Junie. O SKILL.md instalado leva o caminho absoluto do `./scaffold` desta cópia.

Depois de escrever, o `new` gera os ícones (Chrome headless), roda `flutter pub get`, `dart format`,
`cargo fmt` e `git init`. O projeto sai com hot-patch do backend (`./hot.sh`, ver o CLAUDE.md gerado); passo que falha só avisa. Os próximos passos ficam no `CLAUDE.md` gerado.

O manifest é validado antes de escrever qualquer coisa: nomes em snake_case, sem colisão com
classes do Dart/Flutter/template (ex.: `list` viraria `List`) nem com palavras reservadas,
textos sem aspas/`$`/chaves (entram direto em código), cores em `#RRGGBB`, defaults dentro de
min/max. Se algo falhar no meio, a pasta parcial é apagada.

## Como funciona

- `template/`: o projeto modelo, embutido no binário em tempo de compilação. Arquivos que usam a
  sintaxe do template passam pelo minijinja com delimitadores `{= x =}`, `{% %}` e `{# #}` (não
  colidem com Dart, Rust, Kotlin nem com o `{{flutter_js}}` do Flutter); o resto é copiado cru.
  Nos caminhos, `__android_path__` vira o pacote em pastas e arquivos com `__entity__`/`__plural__`
  saem uma vez por entidade (variável `e`).
- `cli/src/manifest.rs`: o manifest, a validação e tudo o que é derivado (nomes do crate/pacote,
  classes, rótulos com gênero, tipos SQL/Rust/Dart, cores que faltam).
- `cli/src/main.rs`: renderiza tudo em memória, escreve, e roda os passos finais.
- `cli/src/skill.rs` e `skill/SKILL.md`: a skill e onde ela é instalada em cada agente.

Mudou o template, a skill ou o CLI? `./build.sh` recompila os binários de todas as plataformas em
`bin/` (precisa de `zig` e `cargo-zigbuild`: `brew install zig && cargo install cargo-zigbuild
--locked`); `./build.sh local` compila só o da máquina. Commite os binários junto com a mudança:
quem clona usa o `./scaffold` sem compilar. Depois de mudar a skill, rode `./scaffold skill install`
de novo. Para validar
uma mudança, gere o exemplo e compile os dois lados:

```bash
./scaffold new examples/tarefas.toml /tmp/t && (cd /tmp/t/server && cargo clippy) && (cd /tmp/t/app && flutter analyze)
```

## Regra dos projetos gerados

O `CLAUDE.md` que o template gera obriga o Claude Code a usar o hot-patch (`./hot.sh`) no backend.
Mudou o fluxo de rodar o servidor no template? Mantenha essa regra e a seção Hot-patch em
`template/CLAUDE.md` coerentes com o que o template faz, e rode `./build.sh`.
