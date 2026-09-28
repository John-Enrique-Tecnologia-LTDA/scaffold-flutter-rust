//! Conexão com o Postgres.

use sea_orm::{ConnectOptions, Database, DatabaseConnection};
use std::time::Duration;

/// Abre o pool. A URL vem de `DATABASE_URL`, com o container local como padrão.
pub async fn connect() -> anyhow::Result<DatabaseConnection> {
    let url = std::env::var("DATABASE_URL").unwrap_or_else(|_| "postgres://{= name =}:{= name =}@localhost:5432/{= name =}".to_string());
    let mut opt = ConnectOptions::new(url);
    opt.max_connections(10).min_connections(1).acquire_timeout(Duration::from_secs(10)).sqlx_logging_level(tracing::log::LevelFilter::Debug);
    Ok(Database::connect(opt).await?)
}
