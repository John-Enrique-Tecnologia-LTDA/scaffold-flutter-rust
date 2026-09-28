//! `scaffold skill`: instala a skill deste CLI (skill/SKILL.md) nos agentes de IA da máquina.
//!
//! O formato é o de Agent Skills (uma pasta com `SKILL.md`, frontmatter `name`/`description`). A
//! pasta compartilhada `~/.agents/skills` é lida por Codex, Cursor, Gemini CLI, OpenCode, GitHub
//! Copilot, Amp e outros, e recebe a skill sempre. Agentes com pasta própria (Claude Code, Windsurf,
//! Kiro...) recebem também na deles, quando detectados pela pasta de configuração: assim nenhum
//! agente vê a skill duplicada e ninguém ganha pasta de um agente que não tem.

use std::{
    fs,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result};

pub const NAME: &str = "scaffold-flutter-rust";
const SKILL: &str = include_str!("../../skill/SKILL.md");
const EXAMPLE: &str = include_str!("../../examples/tarefas.toml");

/// Agentes que leem `~/.agents/skills`: só para dizer quem foi coberto.
const SHARED_READERS: &[(&str, &str)] = &[
    ("OpenAI Codex", ".codex"),
    ("Cursor", ".cursor"),
    ("Gemini CLI", ".gemini"),
    ("OpenCode", ".config/opencode"),
    ("GitHub Copilot", ".copilot"),
    ("Amp", ".config/amp"),
    ("Goose", ".config/goose"),
];

/// Agentes com pasta de skills própria: (nome, pasta que indica que está instalado, pasta de skills).
const OWN_DIRS: &[(&str, &str, &str)] = &[
    ("Claude Code", ".claude", ".claude/skills"),
    ("Windsurf", ".codeium/windsurf", ".codeium/windsurf/skills"),
    ("Kiro", ".kiro", ".kiro/skills"),
    ("Factory Droid", ".factory", ".factory/skills"),
    ("Qwen Code", ".qwen", ".qwen/skills"),
    ("Roo Code", ".roo", ".roo/skills"),
    ("Cline", ".cline", ".cline/skills"),
    ("Junie", ".junie", ".junie/skills"),
];

fn home() -> Result<PathBuf> {
    std::env::var_os("HOME").or_else(|| std::env::var_os("USERPROFILE")).map(PathBuf::from).context("sem HOME nem USERPROFILE")
}

/// Onde a skill vai: a pasta compartilhada e as dos agentes detectados.
fn targets(home: &Path) -> Vec<(String, PathBuf)> {
    let mut out = vec![("pasta compartilhada (~/.agents/skills)".to_string(), home.join(".agents/skills").join(NAME))];
    for (name, marker, dir) in OWN_DIRS {
        if home.join(marker).is_dir() {
            out.push(((*name).to_string(), home.join(dir).join(NAME)));
        }
    }
    out
}

/// O caminho que a skill manda usar: o lançador `scaffold` da raiz do repositório quando o binário
/// roda de `bin/`, senão o próprio executável.
fn binary_path() -> String {
    let Ok(exe) = std::env::current_exe().and_then(fs::canonicalize) else { return "scaffold".into() };
    if let Some(root) = exe.parent().filter(|d| d.ends_with("bin")).and_then(Path::parent) {
        let launcher = root.join(if cfg!(windows) { "scaffold.cmd" } else { "scaffold" });
        if launcher.is_file() {
            return launcher.display().to_string();
        }
    }
    exe.display().to_string()
}

pub fn rendered() -> String {
    SKILL.replace("{{SCAFFOLD_BIN}}", &binary_path())
}

pub fn install(dry_run: bool) -> Result<()> {
    let home = home()?;
    let skill = rendered();
    for (who, dir) in targets(&home) {
        println!("{} {who}: {}", if dry_run { "instalaria em" } else { "·" }, dir.display());
        if dry_run {
            continue;
        }
        fs::create_dir_all(dir.join("examples")).with_context(|| format!("criando {}", dir.display()))?;
        fs::write(dir.join("SKILL.md"), &skill)?;
        fs::write(dir.join("examples/tarefas.toml"), EXAMPLE)?;
    }
    let covered: Vec<&str> = SHARED_READERS.iter().filter(|(_, m)| home.join(m).is_dir()).map(|(n, _)| *n).collect();
    if !covered.is_empty() {
        println!("  lida pela pasta compartilhada: {}", covered.join(", "));
    }
    if !dry_run {
        println!("skill `{NAME}` instalada; os agentes a carregam na próxima sessão");
    }
    Ok(())
}

pub fn uninstall() -> Result<()> {
    let home = home()?;
    // remove de todas as pastas conhecidas, detectadas ou não
    let mut dirs = vec![home.join(".agents/skills").join(NAME)];
    dirs.extend(OWN_DIRS.iter().map(|(_, _, d)| home.join(d).join(NAME)));
    let mut removed = 0;
    for d in dirs.into_iter().filter(|d| d.join("SKILL.md").is_file()) {
        fs::remove_dir_all(&d).with_context(|| format!("removendo {}", d.display()))?;
        println!("· removida de {}", d.display());
        removed += 1;
    }
    if removed == 0 {
        println!("a skill não estava instalada em nenhum agente");
    }
    Ok(())
}
