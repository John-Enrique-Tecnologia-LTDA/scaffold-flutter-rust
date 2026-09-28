//! Endpoints da API. O domínio (as entidades do manifest) é escrito sobre o query builder
//! do SeaORM, um submódulo por recurso; contas ficam em `auth.rs` e `oauth.rs`, em SQL direto
//! pelo sqlx.

{% for e in entities %}mod {= e.plural =};
{% endfor %}
use axum::{
    Json, Router,
    http::{HeaderValue, StatusCode, header},
    response::{IntoResponse, Response},
    routing::{get, post},
};
use serde_json::json;
use tower_http::set_header::SetResponseHeaderLayer;

use crate::{AppState, auth, oauth};

pub struct ApiError(pub StatusCode, pub String);
pub type ApiResult<T> = Result<Json<T>, ApiError>;

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (self.0, Json(json!({"error": self.1}))).into_response()
    }
}

pub fn err(status: StatusCode, msg: impl ToString) -> ApiError {
    ApiError(status, msg.to_string())
}

impl ApiError {
    pub fn unauthorized() -> Self {
        err(StatusCode::UNAUTHORIZED, "não autenticado")
    }
    pub fn not_found() -> Self {
        err(StatusCode::NOT_FOUND, "não encontrado")
    }
    pub fn too_many_requests() -> Self {
        err(StatusCode::TOO_MANY_REQUESTS, "muitas tentativas; aguarde")
    }
    /// 500 genérico: o detalhe vai só para o log, nunca para o cliente.
    pub fn internal(e: impl std::fmt::Display) -> Self {
        tracing::error!(error = %e, "erro interno");
        err(StatusCode::INTERNAL_SERVER_ERROR, "erro interno")
    }
}

impl From<sqlx::Error> for ApiError {
    fn from(e: sqlx::Error) -> Self {
        match e {
            sqlx::Error::RowNotFound => ApiError::not_found(),
            e => ApiError::internal(e),
        }
    }
}

impl From<sea_orm::DbErr> for ApiError {
    fn from(e: sea_orm::DbErr) -> Self {
        let msg = e.to_string();
        if msg.contains("duplicate key") || msg.contains("unique constraint") {
            tracing::warn!("conflito de chave única: {msg}");
            return err(StatusCode::CONFLICT, "já existe um registro com esse valor único");
        }
        ApiError::internal(e)
    }
}

impl From<anyhow::Error> for ApiError {
    fn from(e: anyhow::Error) -> Self {
        ApiError::internal(e)
    }
}

pub fn router(state: AppState) -> Router {
    let api = Router::new()
        // contas
        .route("/api/auth/magic-link", post(auth::magic_link))
        .route("/api/auth/verify", post(auth::verify))
        .route("/api/auth/access-code", post(auth::access_code))
        .route("/api/auth/providers", get(oauth::providers))
        .route("/api/auth/oauth/{provider}/start", get(oauth::start))
        .route("/api/auth/oauth/{provider}/callback", get(oauth::callback))
        .route("/api/auth/oauth/finish", post(oauth::finish))
        .route("/api/auth/oauth/discord/app", post(oauth::app_start))
        .route("/api/auth/oauth/discord/app/finish", post(oauth::app_finish))
        .route("/api/auth/refresh", post(auth::refresh))
        .route("/api/auth/logout", post(auth::logout))
        .route("/api/auth/logout-all", post(auth::logout_all))
        .route("/api/me", get(auth::me).patch(auth::patch_me).delete(auth::delete_me))
{% for e in entities %}        .route("/api/{= e.plural =}", get({= e.plural =}::list).post({= e.plural =}::create))
        .route("/api/{= e.plural =}/{id}", get({= e.plural =}::get).patch({= e.plural =}::patch).delete({= e.plural =}::delete))
{% endfor %}        .layer(SetResponseHeaderLayer::overriding(header::CACHE_CONTROL, HeaderValue::from_static("no-store")))
        .layer(SetResponseHeaderLayer::overriding(header::X_CONTENT_TYPE_OPTIONS, HeaderValue::from_static("nosniff")));

    Router::new().route("/healthz", get(|| async { "ok" })).merge(api).with_state(state)
}
