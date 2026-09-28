//! Entidades do SeaORM, uma por tabela do Postgres. As tabelas de contas (`users`, `sessions`,
//! `magic_links`, `oauth_*`) ficam fora: `auth.rs` e `oauth.rs` falam com elas em SQL direto.

{% for e in entities %}pub mod {= e.name =};
{% endfor %}
pub mod prelude {
{% for e in entities %}    pub use super::{= e.name =}::Entity as {= e.class =};
{% endfor %}}
