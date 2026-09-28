mod auth;
mod config;
mod db;
mod entities;
mod mail;
mod oauth;
mod routes;

use std::{net::SocketAddr, sync::Arc, time::Duration};

use axum::{Router, extract::FromRef};
use sea_orm::DatabaseConnection;
use sqlx::PgPool;
use tower_http::{
    cors::CorsLayer,
    services::{ServeDir, ServeFile},
    trace::TraceLayer,
};

use crate::{config::Config, mail::Mailer};

/// Estado das rotas. O SeaORM e o sqlx dividem o mesmo pool: o domínio usa o query builder,
/// contas usam SQL direto pelo sqlx.
#[derive(Clone)]
pub struct AppState {
    pub db: DatabaseConnection,
    pub pool: PgPool,
    pub cfg: Arc<Config>,
    pub mailer: Arc<Mailer>,
}

/// Os handlers do domínio pedem só `State<DatabaseConnection>`.
impl FromRef<AppState> for DatabaseConnection {
    fn from_ref(s: &AppState) -> Self {
        s.db.clone()
    }
}

/// O que roda uma vez só: ambiente, log, banco, email e a faxina. Com o hot-patch, isto sobrevive
/// aos patches (nada de `std::env::var` na parte quente: o `.env` some depois de um patch).
struct Setup {
    state: AppState,
    static_dir: String,
    port: u16,
}

async fn setup() -> anyhow::Result<Setup> {
    dotenvy::dotenv().ok();
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info,tower_http=info".into()))
        .init();

    let cfg = Config::from_env()?;
    let static_dir = std::env::var("{= env_prefix =}_STATIC").unwrap_or_else(|_| "../app/build/web".into());
    let port: u16 = std::env::var("PORT").ok().and_then(|p| p.parse().ok()).unwrap_or(8080);

    let db = db::connect().await?;
    let pool = db.get_postgres_connection_pool().clone();
    tracing::info!("banco conectado");
    let mailer = Arc::new(Mailer::new(&cfg.jmail_url, &cfg.jmail_api_key)?);

    // faxina de tokens vencidos, uma vez por hora
    let cleanup_pool = pool.clone();
    tokio::spawn(async move {
        loop {
            if let Err(e) = auth::cleanup(&cleanup_pool).await {
                tracing::warn!(error = %e, "faxina falhou");
            }
            if let Err(e) = oauth::cleanup(&cleanup_pool).await {
                tracing::warn!(error = %e, "faxina das entradas por provedor falhou");
            }
            tokio::time::sleep(Duration::from_secs(3600)).await;
        }
    });

    Ok(Setup { state: AppState { db, pool, cfg: Arc::new(cfg), mailer }, static_dir, port })
}

/// A parte quente: o roteador e o servidor HTTP. Com o hot-patch, cada patch derruba esta future
/// e cria outra com o código novo (handlers, rotas, validação), sem refazer o `setup`.
async fn serve(state: AppState, static_dir: String, port: u16) -> anyhow::Result<()> {
    let mut app = Router::new().merge(routes::router(state));

    // Em desenvolvimento o próprio servidor publica o build web do Flutter na raiz, e as
    // rotas desconhecidas caem no index.html (aplicação de página única). Em produção o
    // frontend tem container próprio, o diretório não existe e a API sobe sozinha.
    if std::path::Path::new(&static_dir).is_dir() {
        let index = format!("{static_dir}/index.html");
        let spa = ServeDir::new(&static_dir).not_found_service(ServeFile::new(index));
        app = app.fallback_service(spa);
        tracing::info!("publicando o frontend de {static_dir}");
    }

    // CORS aberto: a autenticação vai no cabeçalho Authorization, não em cookie, então outra
    // origem não tem credencial nenhuma para aproveitar
    let app = app.layer(CorsLayer::permissive()).layer(TraceLayer::new_for_http());

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!("escutando em http://{addr}");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

#[cfg(not(feature = "hot"))]
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let s = setup().await?;
    serve(s.state, s.static_dir, s.port).await
}

#[cfg(feature = "hot")]
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let s = setup().await?;
    let args = (s.state, s.static_dir, s.port);
    dioxus_devtools::serve_subsecond_with_args(args, |(state, static_dir, port)| async move {
        if let Err(e) = serve(state, static_dir, port).await {
            tracing::error!(error = %e, "servidor caiu");
        }
    })
    .await;
    Ok(())
}
