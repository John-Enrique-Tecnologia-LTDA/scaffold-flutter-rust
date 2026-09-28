//! scaffold: gera um projeto completo Flutter (web + Android) + Rust (axum + SeaORM + Postgres),
//! com autenticação por magic link, Google e Discord, a partir de um manifest TOML.
//!
//! O template (a pasta `template/` do repositório) vai embutido no binário: cada arquivo de texto
//! que usa a sintaxe passa pelo minijinja com delimitadores próprios (`{= x =}`, `{% %}`, `{# #}`, que não colidem com
//! Dart, Rust, Kotlin nem com o `{{flutter_js}}` do Flutter); binários são copiados como estão.
//! Nos caminhos, `__android_path__` vira o pacote Android em pastas, e arquivos com `__entity__` ou
//! `__plural__` no nome saem uma vez por entidade.

mod manifest;
mod skill;

use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
};

use anyhow::{bail, Context, Result};
use clap::{Parser, Subcommand};
use include_dir::{include_dir, Dir, DirEntry};
use minijinja::{syntax::SyntaxConfig, Environment, UndefinedBehavior, Value};

use crate::manifest::{Manifest, TemplateCtx};

static TEMPLATE: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../template");
const EXAMPLE: &str = include_str!("../../examples/tarefas.toml");

#[derive(Parser)]
#[command(name = "scaffold", version, about = "Gera um projeto Flutter + Rust a partir de um manifest")]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Gera o projeto na pasta indicada, que não pode existir.
    New {
        /// O manifest (TOML); `scaffold example` mostra um completo.
        manifest: PathBuf,
        /// Pasta do projeto novo.
        dest: PathBuf,
        /// Só escreve os arquivos: sem ícones, sem `flutter pub get`, sem formatar, sem `git init`.
        #[arg(long)]
        no_post: bool,
    },
    /// Valida o manifest e mostra o que seria gerado, sem escrever nada.
    Check { manifest: PathBuf },
    /// Imprime um manifest de exemplo comentado.
    Example,
    /// A skill deste CLI para agentes de IA (Claude Code, Codex, Cursor, Gemini CLI, Copilot...).
    Skill {
        #[command(subcommand)]
        action: SkillCmd,
    },
}

#[derive(Subcommand)]
enum SkillCmd {
    /// Instala em ~/.agents/skills e nas pastas próprias dos agentes detectados.
    Install {
        /// Só mostra onde instalaria.
        #[arg(long)]
        dry_run: bool,
    },
    /// Remove de todos os agentes.
    Uninstall,
    /// Imprime o SKILL.md.
    Print,
}

fn main() {
    if let Err(e) = run() {
        eprintln!("erro: {e:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    match Cli::parse().cmd {
        Cmd::Example => print!("{EXAMPLE}"),
        Cmd::Skill { action: SkillCmd::Install { dry_run } } => skill::install(dry_run)?,
        Cmd::Skill { action: SkillCmd::Uninstall } => skill::uninstall()?,
        Cmd::Skill { action: SkillCmd::Print } => print!("{}", skill::rendered()),
        Cmd::Check { manifest } => {
            let ctx = load(&manifest)?;
            let files = plan(&ctx)?;
            println!("manifest ok: {} ({}), {} arquivos", ctx.name, ctx.android_id, files.len());
            for e in &ctx.entities {
                println!("  entidade {} → /api/{}", e.name, e.plural);
            }
        }
        Cmd::New { manifest, dest, no_post } => {
            if dest.exists() {
                bail!("{} já existe; o scaffold só gera numa pasta nova", dest.display());
            }
            let ctx = load(&manifest)?;
            let files = plan(&ctx)?;
            write(&dest, &files).inspect_err(|_| {
                // não deixa meio projeto para trás
                let _ = fs::remove_dir_all(&dest);
            })?;
            println!("{} arquivos gerados em {}", files.len(), dest.display());
            if !no_post {
                post(&dest);
            }
            println!("\npróximos passos: veja {}/CLAUDE.md (seção Comandos)", dest.display());
        }
    }
    Ok(())
}

fn load(path: &Path) -> Result<TemplateCtx> {
    let src = fs::read_to_string(path).with_context(|| format!("lendo {}", path.display()))?;
    Manifest::parse(&src)?.context()
}

/// Um arquivo do projeto gerado.
struct Out {
    path: PathBuf,
    bytes: Vec<u8>,
    executable: bool,
}

fn environment() -> Result<Environment<'static>> {
    let mut env = Environment::new();
    env.set_syntax(SyntaxConfig::builder().block_delimiters("{%", "%}").variable_delimiters("{=", "=}").comment_delimiters("{#", "#}").build()?);
    env.set_trim_blocks(true);
    env.set_lstrip_blocks(true);
    env.set_keep_trailing_newline(true);
    env.set_undefined_behavior(UndefinedBehavior::Strict);
    Ok(env)
}

/// Renderiza tudo em memória antes de escrever: erro de template não cria pasta nenhuma.
fn plan(ctx: &TemplateCtx) -> Result<Vec<Out>> {
    let env = environment()?;
    let base = Value::from_serialize(ctx);
    let mut files = Vec::new();
    let mut stack = vec![&TEMPLATE];
    while let Some(dir) = stack.pop() {
        for entry in dir.entries() {
            match entry {
                DirEntry::Dir(d) => stack.push(d),
                DirEntry::File(f) => {
                    let rel = f.path().to_string_lossy().replace("__android_path__", &ctx.android_path);
                    let per_entity = rel.contains("__entity__") || rel.contains("__plural__");
                    let targets: Vec<(String, Value)> = if per_entity {
                        ctx.entities
                            .iter()
                            .map(|e| {
                                let path = rel.replace("__entity__", &e.name).replace("__plural__", &e.plural);
                                (path, minijinja::context! { e => Value::from_serialize(e), ..base.clone() })
                            })
                            .collect()
                    } else {
                        vec![(rel.clone(), base.clone())]
                    };
                    let executable = rel.ends_with("gradlew") || rel.ends_with(".sh");
                    for (path, vars) in targets {
                        let bytes = match std::str::from_utf8(f.contents()) {
                            // só passa pelo template quem usa a sintaxe dele (o gradlew tem `${#…}` do shell)
                            Ok(text) if text.contains("{=") || text.contains("{%") => env.render_str(text, vars).with_context(|| format!("template {}", f.path().display()))?.into_bytes(),
                            _ => f.contents().to_vec(),
                        };
                        files.push(Out { path: PathBuf::from(path), bytes, executable });
                    }
                }
            }
        }
    }
    Ok(files)
}

fn write(dest: &Path, files: &[Out]) -> Result<()> {
    for f in files {
        let p = dest.join(&f.path);
        if let Some(parent) = p.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(&p, &f.bytes).with_context(|| format!("escrevendo {}", p.display()))?;
        #[cfg(unix)]
        if f.executable {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&p, fs::Permissions::from_mode(0o755))?;
        }
    }
    Ok(())
}

/// Os passos depois de escrever. Cada um que falha só avisa: o projeto já está no disco.
fn post(dest: &Path) {
    let step = |what: &str, dir: &Path, cmd: &str, args: &[&str]| {
        print!("· {what}… ");
        match Command::new(cmd).args(args).current_dir(dir).output() {
            Ok(o) if o.status.success() => println!("ok"),
            Ok(o) => println!("falhou\n{}", String::from_utf8_lossy(&o.stderr).lines().take(8).collect::<Vec<_>>().join("\n")),
            Err(e) => println!("pulado ({cmd}: {e})"),
        }
    };
    let app = dest.join("app");
    step("ícones (Chrome headless)", dest, "python3", &["app/tool/icones.py"]);
    step("flutter pub get", &app, "flutter", &["pub", "get"]);
    step("dart format", &app, "dart", &["format", "-l", "160", "lib"]);
    step("cargo fmt", dest, "cargo", &["fmt"]);
    step("git init", dest, "git", &["init", "-q"]);
}
