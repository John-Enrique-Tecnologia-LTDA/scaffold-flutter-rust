//! O manifest (TOML) e o contexto que os templates recebem: tudo o que dá para derivar do manifest
//! é derivado aqui, e tudo o que entra em código gerado é validado antes, para o template não
//! precisar escapar nada.

use anyhow::{bail, ensure, Context, Result};
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Manifest {
    name: String,
    display_name: String,
    description: String,
    tagline: Option<String>,
    org: String,
    domain: String,
    colors: Colors,
    entities: Vec<EntitySpec>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Colors {
    accent: String,
    accent_dark: Option<String>,
    accent_light: Option<String>,
    on_accent: Option<String>,
    glow: Option<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct EntitySpec {
    name: String,
    plural: Option<String>,
    label: String,
    label_plural: String,
    #[serde(default = "masculine")]
    gender: String,
    #[serde(default = "folder")]
    icon: String,
    fields: Vec<FieldSpec>,
}

fn masculine() -> String {
    "m".into()
}
fn folder() -> String {
    "folder".into()
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct FieldSpec {
    name: String,
    #[serde(rename = "type")]
    kind: String,
    label: String,
    required: Option<bool>,
    min: Option<f64>,
    max: Option<f64>,
    default: Option<toml::Value>,
}

// ---------------------------------------------------------------- contexto dos templates

#[derive(Serialize)]
pub struct TemplateCtx {
    pub name: String,
    display_name: String,
    description: String,
    tagline: String,
    org: String,
    domain: String,
    pub android_id: String,
    pub android_path: String,
    dart_pkg: String,
    #[serde(rename = "crate")]
    crate_: String,
    crate_ident: String,
    env_prefix: String,
    class_prefix: String,
    initial: String,
    colors: ColorsCtx,
    pub entities: Vec<Entity>,
}

#[derive(Serialize)]
struct ColorsCtx {
    accent: String,
    accent_dark: String,
    accent_light: String,
    on_accent: String,
    glow: String,
    accent_rgb: String,
}

#[derive(Serialize, Clone)]
pub struct Entity {
    pub name: String,
    pub plural: String,
    class: String,
    class_plural: String,
    camel: String,
    camel_plural: String,
    route: String,
    icon: String,
    label: String,
    label_plural: String,
    label_lower: String,
    label_plural_lower: String,
    new_label: String,
    none_label: String,
    deleted_label: String,
    title: Field,
    fields: Vec<Field>,
}

#[derive(Serialize, Clone)]
struct Field {
    name: String,
    camel: String,
    kind: String,
    label: String,
    label_lower: String,
    required: bool,
    is_title: bool,
    min: Option<String>,
    max: Option<String>,
    min_lit: Option<String>,
    max_lit: Option<String>,
    rust: &'static str,
    dart: &'static str,
    sql: String,
    default_rust: String,
    default_dart: String,
}

/// Nomes que colidiriam com o que o template já define, com o Dart/Rust ou com as colunas fixas.
const RESERVED_FIELDS: &[&str] = &[
    "id", "owner_id", "created_at", "updated_at", "type", "class", "default", "new", "is", "in", "as", "if", "else", "for", "while", "do", "switch",
    "case", "return", "break", "continue", "true", "false", "null", "this", "super", "var", "final", "const", "static", "void", "enum", "extends",
    "with", "try", "catch", "throw", "fn", "let", "mut", "impl", "struct", "trait", "use", "mod", "pub", "self", "crate", "match", "loop", "move",
    "ref", "where", "async", "await", "dyn", "item", "widget", "context", "mounted", "state",
];
const RESERVED_CLASSES: &[&str] = &[
    "List", "Map", "Set", "String", "Object", "Type", "Future", "Stream", "Iterable", "Duration", "DateTime", "Error", "Exception", "Function",
    "Record", "Symbol", "Uri", "Null", "Never", "Enum", "User", "Tokens", "Me", "Session", "Model", "Entity", "Column", "Relation", "ActiveModel",
    "Card", "Form", "Page", "Icon", "Icons", "Text", "Color", "Theme", "State", "Widget", "Router", "Json", "Path", "Auth", "Account", "Link",
    "Login", "Api", "Palette", "Colors", "Dialog", "Row", "Table", "Chip", "Badge", "Banner",
];

fn is_ident(s: &str, allow_underscore: bool) -> bool {
    let mut cs = s.chars();
    matches!(cs.next(), Some('a'..='z')) && cs.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || (allow_underscore && c == '_')) && !s.ends_with('_') && !s.contains("__")
}

/// Texto que vai direto para dentro de strings Dart/Rust/HTML/JSON: sem aspas, barras, `$`,
/// chaves nem sinais de tag.
fn check_text(what: &str, s: &str) -> Result<()> {
    ensure!(!s.trim().is_empty(), "{what}: vazio");
    if let Some(c) = s.chars().find(|c| c.is_control() || matches!(c, '\'' | '"' | '\\' | '$' | '{' | '}' | '<' | '>' | '`')) {
        bail!("{what}: caractere não permitido {c:?} em {s:?}");
    }
    Ok(())
}

fn pascal(snake: &str) -> String {
    snake.split('_').map(|p| p[..1].to_uppercase() + &p[1..]).collect()
}

fn camel(snake: &str) -> String {
    let p = pascal(snake);
    p[..1].to_lowercase() + &p[1..]
}

fn lower_first(s: &str) -> String {
    let mut cs = s.chars();
    cs.next().map(|c| c.to_lowercase().collect::<String>() + cs.as_str()).unwrap_or_default()
}

// ---------------------------------------------------------------- cores

fn parse_hex(what: &str, s: &str) -> Result<[u8; 3]> {
    let h = s.strip_prefix('#').unwrap_or(s);
    ensure!(h.len() == 6 && h.chars().all(|c| c.is_ascii_hexdigit()), "{what}: cor em #RRGGBB, veio {s:?}");
    let b = |i: usize| u8::from_str_radix(&h[i..i + 2], 16).unwrap_or(0);
    Ok([b(0), b(2), b(4)])
}

fn hex(c: [u8; 3]) -> String {
    format!("{:02X}{:02X}{:02X}", c[0], c[1], c[2])
}

/// Mistura `a` com `b`: `t` = 0 é `a`, 1 é `b`.
fn mix(a: [u8; 3], b: [u8; 3], t: f64) -> [u8; 3] {
    let m = |x: u8, y: u8| (f64::from(x) + (f64::from(y) - f64::from(x)) * t).round().clamp(0.0, 255.0) as u8;
    [m(a[0], b[0]), m(a[1], b[1]), m(a[2], b[2])]
}

fn color(what: &str, given: Option<&String>, derived: [u8; 3]) -> Result<String> {
    Ok(match given {
        Some(s) => hex(parse_hex(what, s)?),
        None => hex(derived),
    })
}

// ---------------------------------------------------------------- campos

fn build_field(e: &str, f: &FieldSpec, is_title: bool) -> Result<Field> {
    let at = format!("entidade {e}, campo {}", f.name);
    ensure!(is_ident(&f.name, true), "{at}: nome em snake_case (minúsculas, dígitos e _)");
    ensure!(!RESERVED_FIELDS.contains(&f.name.as_str()), "{at}: nome reservado");
    check_text(&format!("{at}, label"), &f.label)?;
    let kind = f.kind.as_str();
    let (rust, dart) = match kind {
        "string" | "text" => ("String", "String"),
        "int" => ("i32", "int"),
        "float" => ("f64", "double"),
        "bool" => ("bool", "bool"),
        other => bail!("{at}: tipo {other:?} desconhecido (string, text, int, float, bool)"),
    };
    let textual = matches!(kind, "string" | "text");
    let numeric = matches!(kind, "int" | "float");
    ensure!(f.required.is_none() || textual, "{at}: `required` só vale para string e text");
    ensure!(f.min.is_none() || numeric, "{at}: `min` só vale para int e float");
    ensure!(f.max.is_none() || textual || numeric, "{at}: `max` não vale para bool");
    if let (Some(a), Some(b)) = (f.min, f.max) {
        ensure!(a <= b, "{at}: min maior que max");
    }
    if kind == "int" || textual {
        for v in [f.min, f.max].into_iter().flatten() {
            ensure!(v.fract() == 0.0 && v.abs() < 2e9, "{at}: min/max inteiros para {kind}");
        }
    }
    if textual && let Some(m) = f.max {
        ensure!(m >= 1.0, "{at}: max precisa ser pelo menos 1");
    }
    let required = is_title || f.required.unwrap_or(false);
    let num = |v: f64| if kind == "float" { format!("{v:?}") } else { format!("{}", v as i64) };

    let (sql_default, default_rust, default_dart) = match (kind, &f.default) {
        (_, None) if textual => ("''".to_string(), "String::new()".to_string(), "''".to_string()),
        (_, Some(toml::Value::String(s))) if textual => {
            check_text(&format!("{at}, default"), s)?;
            (format!("'{s}'"), format!("String::from(\"{s}\")"), format!("'{s}'"))
        }
        ("bool", None) => ("false".into(), "false".into(), "false".into()),
        ("bool", Some(toml::Value::Boolean(b))) => (b.to_string(), b.to_string(), b.to_string()),
        ("int" | "float", d) => {
            let v = match d {
                None => f.min.filter(|m| *m > 0.0).unwrap_or(0.0),
                Some(toml::Value::Integer(i)) => *i as f64,
                Some(toml::Value::Float(x)) if kind == "float" => *x,
                Some(_) => bail!("{at}: default precisa ser número {}", if kind == "int" { "inteiro" } else { "" }),
            };
            ensure!(f.min.is_none_or(|m| v >= m) && f.max.is_none_or(|m| v <= m), "{at}: default fora de min/max");
            (num(v), num(v), num(v))
        }
        _ => bail!("{at}: default com tipo errado para {kind}"),
    };
    let sql_type = match kind {
        "string" | "text" => "TEXT",
        "int" => "INTEGER",
        "float" => "DOUBLE PRECISION",
        _ => "BOOLEAN",
    };
    Ok(Field {
        name: f.name.clone(),
        camel: camel(&f.name),
        kind: kind.into(),
        label: f.label.clone(),
        label_lower: lower_first(&f.label),
        required,
        is_title,
        min: f.min.map(num),
        max: f.max.map(num),
        min_lit: f.min.map(num),
        max_lit: f.max.map(num),
        rust,
        dart,
        sql: format!("{sql_type} NOT NULL DEFAULT {sql_default}"),
        default_rust,
        default_dart,
    })
}

fn build_entity(i: usize, s: &EntitySpec) -> Result<Entity> {
    let at = format!("entidade {}", s.name);
    ensure!(is_ident(&s.name, true), "{at}: nome em snake_case, singular");
    let plural = s.plural.clone().unwrap_or_else(|| format!("{}s", s.name));
    ensure!(is_ident(&plural, true) && plural != s.name, "{at}: plural em snake_case e diferente do singular");
    let class = pascal(&s.name);
    let class_plural = pascal(&plural);
    for c in [&class, &class_plural] {
        ensure!(!RESERVED_CLASSES.contains(&c.as_str()), "{at}: {c} colide com uma classe do Dart, do Flutter ou do template; escolha outro nome");
    }
    check_text(&format!("{at}, label"), &s.label)?;
    check_text(&format!("{at}, label_plural"), &s.label_plural)?;
    ensure!(s.icon.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_') && !s.icon.is_empty(), "{at}: icon é o nome de um Icons.* (ex.: task_alt)");
    let fem = match s.gender.as_str() {
        "m" => false,
        "f" => true,
        g => bail!("{at}: gender {g:?} (use \"m\" ou \"f\")"),
    };
    ensure!(!s.fields.is_empty(), "{at}: sem campos");
    let title_idx = s.fields.iter().position(|f| f.kind == "string").with_context(|| format!("{at}: precisa de um campo `string` (o título)"))?;
    let mut seen = std::collections::HashSet::new();
    let mut fields = Vec::new();
    for (j, f) in s.fields.iter().enumerate() {
        ensure!(seen.insert(f.name.as_str()), "{at}: campo {} repetido", f.name);
        fields.push(build_field(&s.name, f, j == title_idx)?);
    }
    let label_lower = lower_first(&s.label);
    Ok(Entity {
        name: s.name.clone(),
        camel: camel(&s.name),
        camel_plural: camel(&plural),
        route: if i == 0 { "/".into() } else { format!("/{}", plural.replace('_', "-")) },
        plural,
        class,
        class_plural,
        icon: s.icon.clone(),
        label: s.label.clone(),
        label_plural: s.label_plural.clone(),
        new_label: format!("{} {label_lower}", if fem { "Nova" } else { "Novo" }),
        none_label: format!("{} {label_lower} ainda", if fem { "Nenhuma" } else { "Nenhum" }),
        deleted_label: format!("{} {}.", s.label, if fem { "apagada" } else { "apagado" }),
        label_plural_lower: lower_first(&s.label_plural),
        label_lower,
        title: fields[title_idx].clone(),
        fields,
    })
}

impl Manifest {
    pub fn parse(src: &str) -> Result<Self> {
        toml::from_str(src).context("manifest inválido")
    }

    pub fn context(&self) -> Result<TemplateCtx> {
        ensure!(is_ident(&self.name, false) && self.name.len() <= 30, "name: minúsculas e dígitos, começando por letra, até 30 (veio {:?})", self.name);
        check_text("display_name", &self.display_name)?;
        check_text("description", &self.description)?;
        let tagline = self.tagline.clone().unwrap_or_else(|| self.description.clone());
        check_text("tagline", &tagline)?;
        ensure!(self.org.split('.').count() >= 2 && self.org.split('.').all(|p| is_ident(p, false)), "org: domínio invertido em minúsculas (ex.: tech.johnenrique)");
        ensure!(
            self.domain.split('.').count() >= 2 && self.domain.split('.').all(|p| !p.is_empty() && p.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')),
            "domain: host em minúsculas (ex.: app.exemplo.com)"
        );
        ensure!(!self.entities.is_empty(), "entities: declare pelo menos uma");
        let mut entities = Vec::new();
        let mut seen = std::collections::HashSet::new();
        for (i, e) in self.entities.iter().enumerate() {
            let e = build_entity(i, e)?;
            ensure!(seen.insert(e.name.clone()) && seen.insert(e.plural.clone()), "entidade {} repetida (ou plural igual ao nome de outra)", e.name);
            entities.push(e);
        }

        let accent = parse_hex("colors.accent", &self.colors.accent)?;
        let c = &self.colors;
        let colors = ColorsCtx {
            accent: hex(accent),
            accent_dark: color("colors.accent_dark", c.accent_dark.as_ref(), mix(accent, [0, 0, 0], 0.4))?,
            accent_light: color("colors.accent_light", c.accent_light.as_ref(), mix(accent, [255, 255, 255], 0.35))?,
            on_accent: color("colors.on_accent", c.on_accent.as_ref(), mix(accent, [0, 0, 0], 0.85))?,
            glow: color("colors.glow", c.glow.as_ref(), mix([0x0E, 0x10, 0x13], accent, 0.15))?,
            accent_rgb: format!("{}, {}, {}", accent[0], accent[1], accent[2]),
        };
        let android_id = format!("{}.{}", self.org, self.name);
        Ok(TemplateCtx {
            android_path: android_id.replace('.', "/"),
            android_id,
            dart_pkg: format!("{}_app", self.name),
            crate_: format!("{}-server", self.name),
            crate_ident: format!("{}_server", self.name),
            env_prefix: self.name.to_uppercase(),
            class_prefix: pascal(&self.name),
            initial: self.display_name.trim().chars().next().map(|c| c.to_uppercase().collect()).unwrap_or_default(),
            name: self.name.clone(),
            display_name: self.display_name.clone(),
            description: self.description.clone(),
            tagline,
            org: self.org.clone(),
            domain: self.domain.clone(),
            colors,
            entities,
        })
    }
}
