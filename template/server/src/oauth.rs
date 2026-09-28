//! Entrar com Google e com Discord, pelo fluxo de código do OAuth, conduzido aqui no servidor.
//!
//! 1. O app abre `GET /api/auth/oauth/{provedor}/start?platform=web|android&challenge=` (na web, na
//!    mesma aba; no Android, numa aba do Chrome sobre o app). `challenge` é o SHA-256 (base64url)
//!    de um segredo que só o app conhece.
//! 2. O servidor guarda o estado (10 min, uso único) e manda para o provedor.
//! 3. O provedor volta em `…/callback` com o código; o servidor troca o código pelo acesso, lê o
//!    email da conta e, se o provedor diz que o email é verificado, grava uma entrada de uso único
//!    (2 min) e devolve o app: na web `/login?oauth=`, no Android o esquema do app
//!    (`{= android_id =}://oauth?oauth=`).
//! 4. O app troca a entrada por uma sessão em `POST /api/auth/oauth/finish {token, verifier}`,
//!    provando que foi ele quem começou (o SHA-256 do `verifier` tem de bater com o `challenge`).
//!    Quem intercepta o retorno (outro app com o mesmo esquema, um link repassado) não entra.
//!
//! No Android, pela aba do Chrome a pessoa teria de entrar no Discord pelo navegador, com email e
//! senha (quase ninguém fica logado nele pelo navegador do celular).
//! Com o app do Discord instalado, o {= display_name =} pede o endereço em `POST …/discord/app`, abre no app
//! do Discord (já logado; o esquema `discord://action/oauth2/authorize` que o app dele atende) e
//! recebe a volta pelo esquema `discord-{id}:/authorize/callback`, que o Discord documenta para
//! apps de celular; `POST …/discord/app/finish {code, state, verifier}`
//! troca o código por uma sessão, com a mesma prova do app.
//!
//! A conta é o email, como no magic link: entrar pelo Google ou pelo Discord com o mesmo email cai
//! na mesma conta. Sem email verificado no
//! provedor, não entra. Provedor sem credencial no ambiente fica desligado (`/api/auth/providers`).

use std::time::Duration;

use axum::{
    Json,
    extract::{Path, Query, State},
    http::HeaderMap,
    response::{IntoResponse, Redirect, Response},
};
use base64::Engine;
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};

use crate::{
    AppState,
    auth::{self, Tokens},
    config::Config,
    routes::ApiError,
};

static HTTP: Lazy<reqwest::Client> = Lazy::new(|| reqwest::Client::builder().timeout(Duration::from_secs(15)).build().expect("cliente HTTP do OAuth"));

const STATE_TTL_MIN: i32 = 10;
const GRANT_TTL_SECS: f64 = 120.0;
const STARTS_PER_IP_HOUR: i64 = 60;
/// Para onde o Android volta: a atividade do flutter_web_auth_2 escuta este esquema.
const ANDROID_RETURN: &str = "{= android_id =}://oauth";

#[derive(Clone, Copy, PartialEq)]
pub enum Provider {
    Google,
    Discord,
}

impl Provider {
    fn parse(s: &str) -> Option<Self> {
        match s {
            "google" => Some(Self::Google),
            "discord" => Some(Self::Discord),
            _ => None,
        }
    }
    fn name(self) -> &'static str {
        match self {
            Self::Google => "google",
            Self::Discord => "discord",
        }
    }
    fn client(self, cfg: &Config) -> Option<&OAuthClient> {
        match self {
            Self::Google => cfg.google.as_ref(),
            Self::Discord => cfg.discord.as_ref(),
        }
    }
}

/// Credencial de um provedor (cliente confidencial: o segredo fica só aqui).
#[derive(Clone)]
pub struct OAuthClient {
    pub id: String,
    pub secret: String,
}

#[derive(Serialize)]
pub struct Providers {
    providers: Vec<&'static str>,
}

/// Quais botões o app mostra.
pub async fn providers(State(s): State<AppState>) -> Json<Providers> {
    let providers = [Provider::Google, Provider::Discord].into_iter().filter(|p| p.client(&s.cfg).is_some()).map(Provider::name).collect();
    Json(Providers { providers })
}

fn callback_url(cfg: &Config, p: Provider) -> String {
    format!("{}/api/auth/oauth/{}/callback", cfg.app_base_url, p.name())
}

fn b64(bytes: &[u8]) -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}

/// O desafio do PKCE (S256) de um segredo.
fn challenge_of(verifier: &str) -> String {
    b64(&Sha256::digest(verifier.as_bytes()))
}

/// SHA-256 em base64url tem 43 caracteres do alfabeto do base64url.
fn plausible_challenge(c: &str) -> bool {
    c.len() == 43 && c.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
}

#[derive(Deserialize)]
pub struct StartQuery {
    platform: String,
    challenge: String,
}

/// Começa a entrada: guarda o estado e manda para o provedor.
pub async fn start(State(s): State<AppState>, Path(provider): Path<String>, headers: HeaderMap, Query(q): Query<StartQuery>) -> Result<Response, ApiError> {
    let p = Provider::parse(&provider).ok_or_else(ApiError::not_found)?;
    let client = p.client(&s.cfg).ok_or_else(ApiError::not_found)?;
    if !matches!(q.platform.as_str(), "web" | "android") || !plausible_challenge(&q.challenge) {
        return Err(bad_request());
    }
    let url = begin(&s, p, client, &q.platform, &q.challenge, &callback_url(&s.cfg, p), &headers).await?;
    Ok(Redirect::to(url.as_str()).into_response())
}

fn bad_request() -> ApiError {
    crate::routes::err(axum::http::StatusCode::BAD_REQUEST, "pedido de entrada inválido")
}

/// Guarda o estado de uma entrada nova e monta o endereço de autorização do provedor.
async fn begin(
    s: &AppState,
    p: Provider,
    client: &OAuthClient,
    platform: &str,
    challenge: &str,
    redirect: &str,
    headers: &HeaderMap,
) -> Result<reqwest::Url, ApiError> {
    let ip = auth::client_ip(headers);
    if let Some(ip) = &ip {
        let (n,): (i64,) =
            sqlx::query_as("SELECT count(*) FROM oauth_states WHERE ip = $1 AND created_at > now() - interval '1 hour'").bind(ip).fetch_one(&s.pool).await?;
        if n >= STARTS_PER_IP_HOUR {
            return Err(ApiError::too_many_requests());
        }
    }

    let (state, state_hash) = auth::generate_token();
    // PKCE também com o provedor (os dois aceitam, só S256)
    let (pkce, _) = auth::generate_token();
    sqlx::query(
        "INSERT INTO oauth_states (state_hash, provider, platform, challenge, pkce_verifier, ip, expires_at)
         VALUES ($1, $2, $3, $4, $5, $6, now() + make_interval(mins => $7))",
    )
    .bind(&state_hash)
    .bind(p.name())
    .bind(platform)
    .bind(challenge)
    .bind(&pkce)
    .bind(&ip)
    .bind(STATE_TTL_MIN)
    .execute(&s.pool)
    .await?;

    match p {
        Provider::Google => reqwest::Url::parse_with_params(
            "https://accounts.google.com/o/oauth2/v2/auth",
            &[
                ("client_id", client.id.as_str()),
                ("redirect_uri", redirect),
                ("response_type", "code"),
                ("scope", "openid email profile"),
                ("state", state.as_str()),
                ("code_challenge", challenge_of(&pkce).as_str()),
                ("code_challenge_method", "S256"),
                ("prompt", "select_account"),
            ],
        ),
        Provider::Discord => reqwest::Url::parse_with_params(
            "https://discord.com/oauth2/authorize",
            &[
                ("client_id", client.id.as_str()),
                ("redirect_uri", redirect),
                ("response_type", "code"),
                ("scope", "identify email"),
                ("state", state.as_str()),
                ("code_challenge", challenge_of(&pkce).as_str()),
                ("code_challenge_method", "S256"),
                // quem já autorizou antes não vê a tela de permissão de novo
                ("prompt", "none"),
            ],
        ),
    }
    .map_err(ApiError::internal)
}

/// Retorno do app do Discord no Android: o esquema que o próprio Discord documenta para apps de
/// celular. Quem autoriza é o app do Discord, já logado, e ele devolve direto para o {= display_name =}.
fn discord_app_redirect(client: &OAuthClient) -> String {
    format!("discord-{}:/authorize/callback", client.id)
}

#[derive(Deserialize)]
pub struct AppStartRequest {
    challenge: String,
}

#[derive(Serialize)]
pub struct AppStart {
    url: String,
}

/// Android com o app do Discord: o endereço de autorização no esquema do app do Discord
/// (`discord://action/oauth2/authorize`, os mesmos parâmetros do endereço web), para o {= display_name =}
/// abrir nele. A volta chega pelo esquema `discord-{id}:` e termina em [`app_finish`].
pub async fn app_start(State(s): State<AppState>, headers: HeaderMap, Json(b): Json<AppStartRequest>) -> Result<Json<AppStart>, ApiError> {
    let client = s.cfg.discord.as_ref().ok_or_else(ApiError::not_found)?;
    if !plausible_challenge(&b.challenge) {
        return Err(bad_request());
    }
    let url = begin(&s, Provider::Discord, client, "discord-app", &b.challenge, &discord_app_redirect(client), &headers).await?;
    let query = url.query().unwrap_or_default();
    Ok(Json(AppStart { url: format!("discord://action/oauth2/authorize?{query}") }))
}

#[derive(Deserialize)]
pub struct AppFinishRequest {
    code: String,
    state: String,
    verifier: String,
}

/// Android com o app do Discord: troca o código que o Discord devolveu ao app por uma sessão,
/// com o segredo de quem começou.
pub async fn app_finish(State(s): State<AppState>, headers: HeaderMap, Json(b): Json<AppFinishRequest>) -> Result<Json<Tokens>, ApiError> {
    let client = s.cfg.discord.clone().ok_or_else(ApiError::not_found)?;
    if !auth::plausible_token(&b.state) || b.code.is_empty() || b.code.len() > 2048 || b.verifier.is_empty() || b.verifier.len() > 128 {
        return Err(ApiError::unauthorized());
    }
    let row: Option<(String, String)> = sqlx::query_as(
        "DELETE FROM oauth_states WHERE state_hash = $1 AND provider = 'discord' AND platform = 'discord-app' AND expires_at > now()
         RETURNING challenge, pkce_verifier",
    )
    .bind(auth::hash_token(&b.state))
    .fetch_optional(&s.pool)
    .await?;
    let Some((challenge, pkce)) = row else {
        return Err(ApiError::unauthorized());
    };
    if challenge_of(&b.verifier) != challenge {
        tracing::warn!("entrada pelo app do Discord apresentada sem a prova do app");
        return Err(ApiError::unauthorized());
    }
    let identity = match identify(Provider::Discord, &client, &discord_app_redirect(&client), &b.code, &pkce).await {
        Ok(Some(i)) => i,
        Ok(None) => return Err(crate::routes::err(axum::http::StatusCode::FORBIDDEN, "sem-email")),
        Err(e) => {
            tracing::warn!(provider = "discord", error = %e, "entrada pelo app do Discord falhou");
            return Err(crate::routes::err(axum::http::StatusCode::BAD_GATEWAY, "falhou"));
        }
    };
    let email = auth::normalize_email(&identity.email).map_err(|_| crate::routes::err(axum::http::StatusCode::FORBIDDEN, "sem-email"))?;
    let mut tx = s.pool.begin().await?;
    let tokens = sign_in(&s, &mut tx, &headers, "discord", &email, identity.name).await?;
    tx.commit().await?;
    Ok(Json(tokens))
}

#[derive(Deserialize)]
pub struct CallbackQuery {
    code: Option<String>,
    state: Option<String>,
    error: Option<String>,
}

/// Quem entrou, pelo provedor.
struct Identity {
    email: String,
    name: String,
}

/// Por que a entrada não saiu, no retorno ao app (o app traduz para a mensagem).
#[derive(Clone, Copy)]
enum Failure {
    /// A pessoa desistiu na tela do provedor.
    Canceled,
    /// O estado não existe mais (passou de 10 min, ou já foi usado).
    Expired,
    /// O provedor não tem email verificado para essa conta.
    NoEmail,
    /// Qualquer outra coisa (provedor fora do ar, código recusado).
    Failed,
}

impl Failure {
    fn code(self) -> &'static str {
        match self {
            Self::Canceled => "cancelado",
            Self::Expired => "expirou",
            Self::NoEmail => "sem-email",
            Self::Failed => "falhou",
        }
    }
}

/// Volta do provedor: troca o código, lê o email e devolve o app com a entrada de uso único.
pub async fn callback(State(s): State<AppState>, Path(provider): Path<String>, Query(q): Query<CallbackQuery>) -> Result<Redirect, ApiError> {
    let p = Provider::parse(&provider).ok_or_else(ApiError::not_found)?;
    let client = p.client(&s.cfg).ok_or_else(ApiError::not_found)?.clone();

    // o estado diz para onde voltar; sem ele, volta para a web
    let row: Option<(String, String, String)> = match q.state.as_deref().filter(|t| auth::plausible_token(t)) {
        Some(state) => {
            sqlx::query_as(
                "DELETE FROM oauth_states WHERE state_hash = $1 AND provider = $2 AND expires_at > now()
             RETURNING platform, challenge, pkce_verifier",
            )
            .bind(auth::hash_token(state))
            .bind(p.name())
            .fetch_optional(&s.pool)
            .await?
        }
        None => None,
    };
    let Some((platform, challenge, pkce)) = row else {
        return Ok(back(&s.cfg, "web", Err(Failure::Expired)));
    };
    if q.error.is_some() {
        return Ok(back(&s.cfg, &platform, Err(Failure::Canceled)));
    }
    let Some(code) = q.code.filter(|c| !c.is_empty() && c.len() <= 2048) else {
        return Ok(back(&s.cfg, &platform, Err(Failure::Failed)));
    };

    let identity = match identify(p, &client, &callback_url(&s.cfg, p), &code, &pkce).await {
        Ok(Some(i)) => i,
        Ok(None) => return Ok(back(&s.cfg, &platform, Err(Failure::NoEmail))),
        Err(e) => {
            tracing::warn!(provider = p.name(), error = %e, "entrada pelo provedor falhou");
            return Ok(back(&s.cfg, &platform, Err(Failure::Failed)));
        }
    };
    let Ok(email) = auth::normalize_email(&identity.email) else {
        return Ok(back(&s.cfg, &platform, Err(Failure::NoEmail)));
    };

    let (token, token_hash) = auth::generate_token();
    sqlx::query(
        "INSERT INTO oauth_grants (token_hash, provider, email, name, challenge, expires_at)
         VALUES ($1, $2, $3, $4, $5, now() + make_interval(secs => $6))",
    )
    .bind(&token_hash)
    .bind(p.name())
    .bind(&email)
    .bind(&identity.name)
    .bind(&challenge)
    .bind(GRANT_TTL_SECS)
    .execute(&s.pool)
    .await?;
    Ok(back(&s.cfg, &platform, Ok(&token)))
}

/// O retorno ao app: a entrada, ou o motivo da falha.
fn back(cfg: &Config, platform: &str, result: Result<&str, Failure>) -> Redirect {
    let (key, value) = match result {
        Ok(token) => ("oauth", token),
        Err(f) => ("erro", f.code()),
    };
    let base = if platform == "android" { ANDROID_RETURN.to_string() } else { format!("{}/login", cfg.app_base_url) };
    Redirect::to(&format!("{base}?{key}={value}"))
}

/// Troca o código e lê a conta no provedor. `None` quando não há email verificado.
async fn identify(p: Provider, client: &OAuthClient, redirect: &str, code: &str, pkce: &str) -> anyhow::Result<Option<Identity>> {
    let http = &*HTTP;
    let token_url = match p {
        Provider::Google => "https://oauth2.googleapis.com/token",
        Provider::Discord => "https://discord.com/api/oauth2/token",
    };
    let form = [
        ("grant_type", "authorization_code"),
        ("code", code),
        ("redirect_uri", redirect),
        ("client_id", client.id.as_str()),
        ("client_secret", client.secret.as_str()),
        ("code_verifier", pkce),
    ];
    let r = http.post(token_url).form(&form).send().await?;
    if !r.status().is_success() {
        let status = r.status();
        let body = r.text().await.unwrap_or_default();
        anyhow::bail!("troca do código recusada ({status}): {}", body.chars().take(300).collect::<String>());
    }
    let tok: Value = r.json().await?;
    let access = tok["access_token"].as_str().ok_or_else(|| anyhow::anyhow!("resposta sem access_token"))?;

    let user_url = match p {
        Provider::Google => "https://openidconnect.googleapis.com/v1/userinfo",
        Provider::Discord => "https://discord.com/api/users/@me",
    };
    let r = http.get(user_url).bearer_auth(access).send().await?;
    if !r.status().is_success() {
        anyhow::bail!("leitura da conta recusada ({})", r.status());
    }
    let u: Value = r.json().await?;
    Ok(identity_of(p, &u))
}

/// O email (se verificado) e o nome de exibição, no formato de cada provedor.
fn identity_of(p: Provider, u: &Value) -> Option<Identity> {
    let (verified, name) = match p {
        Provider::Google => (u["email_verified"].as_bool() == Some(true), u["name"].as_str()),
        Provider::Discord => (u["verified"].as_bool() == Some(true), u["global_name"].as_str().or(u["username"].as_str())),
    };
    let email = u["email"].as_str().filter(|e| verified && !e.is_empty())?;
    Some(Identity { email: email.to_string(), name: name.unwrap_or_default().trim().chars().take(80).collect() })
}

#[derive(Deserialize)]
pub struct FinishRequest {
    token: String,
    verifier: String,
}

/// Troca a entrada por uma sessão, se quem pede é o app que começou.
pub async fn finish(State(s): State<AppState>, headers: HeaderMap, Json(b): Json<FinishRequest>) -> Result<Json<Tokens>, ApiError> {
    if !auth::plausible_token(&b.token) || b.verifier.is_empty() || b.verifier.len() > 128 {
        return Err(ApiError::unauthorized());
    }
    let mut tx = s.pool.begin().await?;
    let row: Option<(String, String, String, String)> = sqlx::query_as(
        "UPDATE oauth_grants SET used_at = now()
         WHERE token_hash = $1 AND used_at IS NULL AND expires_at > now()
         RETURNING provider, email, name, challenge",
    )
    .bind(auth::hash_token(&b.token))
    .fetch_optional(&mut *tx)
    .await?;
    let Some((provider, email, name, challenge)) = row else {
        return Err(ApiError::unauthorized());
    };
    if challenge_of(&b.verifier) != challenge {
        // a entrada morre mesmo assim: quem tem o token sem o segredo não tenta de novo
        tx.commit().await?;
        tracing::warn!(provider, "entrada pelo provedor apresentada sem a prova do app");
        return Err(ApiError::unauthorized());
    }

    let tokens = sign_in(&s, &mut tx, &headers, &provider, &email, name).await?;
    tx.commit().await?;
    Ok(Json(tokens))
}

/// Abre a sessão do email provado pelo provedor; conta sem nome ganha o de lá (quem já tem nome
/// fica com o seu).
async fn sign_in(
    s: &AppState,
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    headers: &HeaderMap,
    provider: &str,
    email: &str,
    name: String,
) -> Result<Tokens, ApiError> {
    let (mut u, sid, refresh) = auth::sign_in_proven_email(s, tx, email, headers).await?;
    if u.name.trim().is_empty() && !name.is_empty() {
        sqlx::query("UPDATE users SET name = $2 WHERE id = $1").bind(u.id).bind(&name).execute(&mut **tx).await?;
        u.name = name;
    }
    tracing::info!(user = %u.id, provider, "entrada pelo provedor");
    auth::tokens_for(s, u, sid, refresh)
}

/// Faxina: estados e entradas vencidos.
pub async fn cleanup(db: &sqlx::PgPool) -> anyhow::Result<()> {
    sqlx::query("DELETE FROM oauth_states WHERE expires_at < now() - interval '1 day'").execute(db).await?;
    sqlx::query("DELETE FROM oauth_grants WHERE expires_at < now() - interval '1 day'").execute(db).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn desafio_do_pkce_bate_com_o_rfc() {
        // exemplo do RFC 7636, apêndice B
        assert_eq!(challenge_of("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM");
        assert!(plausible_challenge("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"));
        assert!(!plausible_challenge("curto"));
    }

    #[test]
    fn so_entra_com_email_verificado() {
        let g = |v: bool| json!({"sub": "1", "email": "a@b.com", "email_verified": v, "name": "Ana"});
        assert_eq!(identity_of(Provider::Google, &g(true)).map(|i| i.name), Some("Ana".into()));
        assert!(identity_of(Provider::Google, &g(false)).is_none());
        let d = json!({"id": "9", "username": "ana_b", "global_name": null, "email": "a@b.com", "verified": true});
        assert_eq!(identity_of(Provider::Discord, &d).map(|i| i.name), Some("ana_b".into()));
        assert!(identity_of(Provider::Discord, &json!({"id": "9", "username": "x", "verified": true})).is_none());
    }
}
