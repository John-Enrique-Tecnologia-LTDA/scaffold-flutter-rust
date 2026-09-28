//! Autenticação sem senha, no mesmo desenho do Bulkscan e do Ar Fresco.
//!
//! Fluxo: `POST /api/auth/magic-link {email}` manda um link com um token aleatório de 256 bits
//! (só o SHA-256 vai para o banco, vale 15 min, uso único). O link abre a rota `/entrar` do app
//! (no navegador ou, no Android, o app instalado), que chama `POST /api/auth/verify` e recebe um
//! **JWT de acesso curto (15 min)** e um **refresh token opaco** (30 dias, trocado a cada uso;
//! reusar o anterior derruba a sessão inteira, passado um minuto da troca).
//!
//! Toda rota autenticada usa o extractor [`Auth`], que valida o JWT E confere no banco que a
//! sessão ainda existe: sair vale na hora, não só quando o JWT vence.

use axum::{
    Json,
    extract::{FromRequestParts, State},
    http::{HeaderMap, StatusCode, header, request::Parts},
};
use base64::Engine;
use chrono::{DateTime, Duration, Utc};
use jsonwebtoken::{Algorithm, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx::{FromRow, PgPool};
use uuid::Uuid;

use crate::{
    AppState,
    mail::{EmailAddr, Mail, button_html},
    routes::{ApiError, err},
};

pub const ACCESS_TTL_MIN: i64 = 15;
const MAGIC_TTL_MIN: i64 = 15;
const REFRESH_TTL_DAYS: i64 = 30;
const SESSION_MAX_DAYS: i64 = 90; // teto absoluto, mesmo com uso contínuo
/// Janela depois de uma troca de refresh em que o token anterior ainda não conta como reuso.
const ROTATION_GRACE_SECS: f64 = 60.0;
const MAGIC_PER_EMAIL_HOUR: i64 = 5;
const MAGIC_PER_IP_HOUR: i64 = 30;

/// Abre a sessão de um email cuja posse acabou de ser provada (magic link, provedor ou código de
/// acesso): cria a conta se preciso e abre a sessão.
/// Devolve o usuário, o id da sessão e o refresh token em claro.
pub async fn sign_in_proven_email(
    _s: &AppState,
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    email: &str,
    headers: &HeaderMap,
) -> Result<(User, Uuid, String), ApiError> {
    // conta bloqueada não entra
    let existing: Option<(Option<DateTime<Utc>>,)> =
        sqlx::query_as("SELECT disabled_at FROM users WHERE lower(email) = lower($1)").bind(email).fetch_optional(&mut **tx).await?;
    if let Some((Some(_),)) = existing {
        return Err(err(StatusCode::FORBIDDEN, "conta bloqueada"));
    }

    // conta nova ou existente: provar o email vale como cadastro
    let u = sqlx::query_as::<_, User>(
        "INSERT INTO users (email, last_login_at) VALUES ($1, now())
         ON CONFLICT (lower(email)) DO UPDATE SET last_login_at = now()
         RETURNING id, email, name",
    )
    .bind(email)
    .fetch_one(&mut **tx)
    .await?;

    let (refresh, refresh_hash) = generate_token();
    let (sid,): (Uuid,) = sqlx::query_as(
        "INSERT INTO sessions (user_id, refresh_hash, expires_at, ip, user_agent)
         VALUES ($1, $2, now() + make_interval(days => $3), $4, $5)
         RETURNING id",
    )
    .bind(u.id)
    .bind(&refresh_hash)
    .bind(REFRESH_TTL_DAYS as i32)
    .bind(client_ip(headers))
    .bind(user_agent(headers))
    .fetch_one(&mut **tx)
    .await?;
    Ok((u, sid, refresh))
}

pub fn tokens_for(s: &AppState, u: User, sid: Uuid, refresh: String) -> Result<Tokens, ApiError> {
    Ok(Tokens { access_token: issue_access(s, u.id, sid)?, token_type: "Bearer", expires_in: ACCESS_TTL_MIN * 60, refresh_token: refresh, user: u })
}

// ---------------------------------------------------------------- tokens

/// Token aleatório (32 bytes, base64url) e o hash que vai para o banco.
pub fn generate_token() -> (String, Vec<u8>) {
    let mut bytes = [0u8; 32];
    rand::RngCore::fill_bytes(&mut rand::rngs::OsRng, &mut bytes);
    let token = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes);
    let hash = hash_token(&token);
    (token, hash)
}

pub fn hash_token(token: &str) -> Vec<u8> {
    Sha256::digest(token.as_bytes()).to_vec()
}

/// Token que chega do cliente: tamanho plausível antes de ir para o hash.
pub fn plausible_token(t: &str) -> bool {
    !t.is_empty() && t.len() <= 64
}

#[derive(Serialize, Deserialize)]
struct Claims {
    sub: Uuid, // usuário
    sid: Uuid, // sessão
    iat: i64,
    exp: i64,
}

pub(crate) fn issue_access(s: &AppState, user_id: Uuid, session_id: Uuid) -> anyhow::Result<String> {
    let now = Utc::now();
    let claims = Claims { sub: user_id, sid: session_id, iat: now.timestamp(), exp: (now + Duration::minutes(ACCESS_TTL_MIN)).timestamp() };
    Ok(jsonwebtoken::encode(&Header::new(Algorithm::HS256), &claims, &EncodingKey::from_secret(&s.cfg.jwt_secret))?)
}

fn decode_access(s: &AppState, token: &str) -> Option<Claims> {
    let mut v = Validation::new(Algorithm::HS256);
    v.leeway = 30;
    v.validate_exp = true;
    jsonwebtoken::decode::<Claims>(token, &DecodingKey::from_secret(&s.cfg.jwt_secret), &v).ok().map(|d| d.claims)
}

// ---------------------------------------------------------------- auxiliares

/// Minúsculo e sem espaços nas pontas. Recusa o que não parece email ou traz quebra de linha
/// (injeção de cabeçalho no envio).
pub fn normalize_email(raw: &str) -> Result<String, ApiError> {
    let e = raw.trim().to_lowercase();
    let ok = e.len() >= 5
        && e.len() <= 254
        && e.matches('@').count() == 1
        && !e.starts_with('@')
        && !e.ends_with('@')
        && e.split('@').nth(1).is_some_and(|d| d.contains('.') && !d.starts_with('.') && !d.ends_with('.'))
        && !e.chars().any(|c| c.is_whitespace() || c.is_control() || matches!(c, ',' | ';' | '<' | '>'));
    if ok { Ok(e) } else { Err(err(StatusCode::BAD_REQUEST, "email inválido")) }
}

/// IP do cliente atrás do Traefik: X-Real-Ip, senão o primeiro do X-Forwarded-For.
pub fn client_ip(h: &HeaderMap) -> Option<String> {
    let get = |k: &str| h.get(k).and_then(|v| v.to_str().ok()).map(|s| s.to_string());
    get("x-real-ip")
        .or_else(|| get("x-forwarded-for").and_then(|v| v.split(',').next().map(|s| s.trim().to_string())))
        .filter(|s| !s.is_empty() && s.len() <= 64)
}

fn user_agent(h: &HeaderMap) -> Option<String> {
    h.get(header::USER_AGENT).and_then(|v| v.to_str().ok()).map(|s| s.chars().take(256).collect())
}

// ---------------------------------------------------------------- extractor

/// Quem está chamando. Vale só se o JWT confere E a sessão ainda está viva no banco.
#[derive(Clone, Debug)]
pub struct Auth {
    pub user_id: Uuid,
    pub session_id: Uuid,
}

impl FromRequestParts<AppState> for Auth {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, s: &AppState) -> Result<Self, Self::Rejection> {
        let raw = parts
            .headers
            .get(header::AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.strip_prefix("Bearer "))
            .ok_or_else(ApiError::unauthorized)?;
        authenticate(s, raw).await
    }
}

/// Valida o JWT de acesso e confere no banco que a sessão continua viva. Serve ao extractor e
/// a um WebSocket, que recebe o token na primeira mensagem (navegador não põe cabeçalho
/// `Authorization` em WebSocket).
pub async fn authenticate(s: &AppState, raw: &str) -> Result<Auth, ApiError> {
    let c = decode_access(s, raw).ok_or_else(ApiError::unauthorized)?;
    // sessão revogada (saiu) ou vencida derruba o JWT mesmo dentro dos 15 min
    let alive: Option<(Uuid,)> = sqlx::query_as(
        "SELECT s.id FROM sessions s JOIN users u ON u.id = s.user_id
             WHERE s.id = $1 AND s.user_id = $2 AND s.revoked_at IS NULL AND s.expires_at > now() AND u.disabled_at IS NULL",
    )
    .bind(c.sid)
    .bind(c.sub)
    .fetch_optional(&s.pool)
    .await?;
    if alive.is_none() {
        return Err(ApiError::unauthorized());
    }
    Ok(Auth { user_id: c.sub, session_id: c.sid })
}

// ---------------------------------------------------------------- modelos

#[derive(Serialize, FromRow)]
pub struct User {
    pub id: Uuid,
    pub email: String,
    pub name: String,
}

#[derive(Serialize)]
pub struct Tokens {
    pub access_token: String,
    pub token_type: &'static str,
    pub expires_in: i64,
    pub refresh_token: String,
    pub user: User,
}

// ---------------------------------------------------------------- magic link

#[derive(Deserialize)]
pub struct MagicLinkRequest {
    email: String,
}

/// Responde sempre 202 do mesmo jeito, exista a conta ou não (sem enumeração de emails).
pub async fn magic_link(State(s): State<AppState>, headers: HeaderMap, Json(b): Json<MagicLinkRequest>) -> Result<StatusCode, ApiError> {
    let email = normalize_email(&b.email)?;
    let ip = client_ip(&headers);

    // limite persistente (vale entre réplicas): por email e por IP, na última hora
    let (n_email,): (i64,) = sqlx::query_as("SELECT count(*) FROM magic_links WHERE lower(email) = $1 AND created_at > now() - interval '1 hour'")
        .bind(&email)
        .fetch_one(&s.pool)
        .await?;
    if n_email >= MAGIC_PER_EMAIL_HOUR {
        return Err(ApiError::too_many_requests());
    }
    if let Some(ip) = &ip {
        let (n_ip,): (i64,) =
            sqlx::query_as("SELECT count(*) FROM magic_links WHERE ip = $1 AND created_at > now() - interval '1 hour'").bind(ip).fetch_one(&s.pool).await?;
        if n_ip >= MAGIC_PER_IP_HOUR {
            return Err(ApiError::too_many_requests());
        }
    }

    // a linha só fica se o email sair: falha no envio desfaz, e o link não conta no limite
    // sem ter chegado a ninguém
    let (token, hash) = generate_token();
    let mut tx = s.pool.begin().await?;
    sqlx::query(
        "INSERT INTO magic_links (email, token_hash, expires_at, ip, user_agent)
         VALUES ($1, $2, now() + make_interval(mins => $3), $4, $5)",
    )
    .bind(&email)
    .bind(&hash)
    .bind(MAGIC_TTL_MIN as i32)
    .bind(&ip)
    .bind(user_agent(&headers))
    .execute(&mut *tx)
    .await?;

    let link = format!("{}/entrar?token={token}", s.cfg.app_base_url);
    let text = format!(
        "Olá!\n\nPara entrar no {= display_name =}, abra este link:\n{link}\n\n\
         Ele vale por {MAGIC_TTL_MIN} minutos e só funciona uma vez. Se não foi você que pediu, ignore este email."
    );
    let html = button_html(
        "<p>Olá!</p><p>Para entrar no <b>{= display_name =}</b>, use o botão abaixo:</p>",
        &link,
        "Entrar no {= display_name =}",
        &format!("O link vale por {MAGIC_TTL_MIN} minutos e só funciona uma vez. Se não foi você que pediu, ignore este email."),
    );
    let mail = Mail::simple(
        EmailAddr { email: s.cfg.mail_from.clone(), name: Some(s.cfg.mail_from_name.clone()) },
        &email,
        "Seu link para entrar no {= display_name =}",
        text,
        html,
    );
    // falha no envio é erro de verdade (a pessoa ficaria sem link), mas não pode revelar nada
    // sobre a conta: a resposta é o 500 genérico
    s.mailer.send(mail).await.map_err(ApiError::internal)?;
    tx.commit().await?;
    Ok(StatusCode::ACCEPTED)
}

#[derive(Deserialize)]
pub struct VerifyRequest {
    token: String,
}

/// Troca o token do magic link por uma sessão. O UPDATE condicional garante o uso único:
/// dois cliques ao mesmo tempo, só um leva.
pub async fn verify(State(s): State<AppState>, headers: HeaderMap, Json(b): Json<VerifyRequest>) -> Result<Json<Tokens>, ApiError> {
    if !plausible_token(&b.token) {
        return Err(ApiError::unauthorized());
    }
    let mut tx = s.pool.begin().await?;
    let email: Option<(String,)> = sqlx::query_as(
        "UPDATE magic_links SET used_at = now()
         WHERE token_hash = $1 AND used_at IS NULL AND expires_at > now()
         RETURNING email",
    )
    .bind(hash_token(&b.token))
    .fetch_optional(&mut *tx)
    .await?;
    let Some((email,)) = email else {
        return Err(ApiError::unauthorized());
    };

    let (u, sid, refresh) = sign_in_proven_email(&s, &mut tx, &email, &headers).await?;
    tx.commit().await?;
    tracing::info!(user = %u.id, "entrada por magic link");
    Ok(Json(tokens_for(&s, u, sid, refresh)?))
}

#[derive(Deserialize)]
pub struct AccessCodeRequest {
    email: String,
    code: String,
}

/// Entrada por código de acesso, só para a conta de demonstração configurada (`REVIEW_EMAIL`):
/// quem revisa o app na Play Store não tem como receber o magic link. Sem a configuração, a rota
/// responde 401 a tudo.
pub async fn access_code(State(s): State<AppState>, headers: HeaderMap, Json(b): Json<AccessCodeRequest>) -> Result<Json<Tokens>, ApiError> {
    let Some((email, code)) = s.cfg.review.as_ref() else { return Err(ApiError::unauthorized()) };
    let given = normalize_email(&b.email).map_err(|_| ApiError::unauthorized())?;
    // comparação em tempo constante do hash (o tamanho não vaza)
    let same_code: bool =
        Sha256::digest(b.code.trim().as_bytes()).iter().zip(Sha256::digest(code.as_bytes()).iter()).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0;
    if given != *email || !same_code {
        tracing::warn!("código de acesso recusado");
        return Err(ApiError::unauthorized());
    }
    let mut tx = s.pool.begin().await?;
    let (u, sid, refresh) = sign_in_proven_email(&s, &mut tx, email, &headers).await?;
    tx.commit().await?;
    tracing::info!(user = %u.id, "entrada por código de acesso");
    Ok(Json(tokens_for(&s, u, sid, refresh)?))
}

// ---------------------------------------------------------------- refresh e saída

#[derive(Deserialize)]
pub struct RefreshRequest {
    refresh_token: String,
}

#[derive(FromRow)]
struct SessionRow {
    id: Uuid,
    user_id: Uuid,
    created_at: DateTime<Utc>,
}

/// Rotação: o refresh apresentado morre e nasce outro. Se o apresentado é o ANTERIOR de
/// alguma sessão, é reuso (vazou): a sessão é revogada e o pedido negado.
pub async fn refresh(State(s): State<AppState>, headers: HeaderMap, Json(b): Json<RefreshRequest>) -> Result<Json<Tokens>, ApiError> {
    if !plausible_token(&b.refresh_token) {
        return Err(ApiError::unauthorized());
    }
    let hash = hash_token(&b.refresh_token);
    let mut tx = s.pool.begin().await?;

    let current = sqlx::query_as::<_, SessionRow>(
        "SELECT s.id, s.user_id, s.created_at FROM sessions s
         WHERE s.refresh_hash = $1 AND s.revoked_at IS NULL AND s.expires_at > now()
           AND NOT EXISTS (SELECT 1 FROM users u WHERE u.id = s.user_id AND u.disabled_at IS NOT NULL)
         FOR UPDATE OF s",
    )
    .bind(&hash)
    .fetch_optional(&mut *tx)
    .await?;

    let Some(session) = current else {
        // No navegador as abas dividem a sessão: duas renovando juntas apresentam o mesmo token,
        // e a segunda chega com o anterior. Logo depois da troca isso é corrida entre abas, não
        // vazamento: 409 sem revogar, e o app relê o token novo que a outra aba gravou.
        let (just_rotated,): (bool,) = sqlx::query_as(
            "SELECT EXISTS (SELECT 1 FROM sessions WHERE previous_refresh_hash = $1 AND revoked_at IS NULL
                                                    AND last_used_at > now() - make_interval(secs => $2))",
        )
        .bind(&hash)
        .bind(ROTATION_GRACE_SECS)
        .fetch_one(&mut *tx)
        .await?;
        if just_rotated {
            return Err(err(StatusCode::CONFLICT, "sessão renovada agora há pouco; use o token novo"));
        }
        // reuso do token anterior fora dessa janela: alguém usou uma cópia, a sessão inteira cai
        let reuse =
            sqlx::query("UPDATE sessions SET revoked_at = now() WHERE previous_refresh_hash = $1 AND revoked_at IS NULL").bind(&hash).execute(&mut *tx).await?;
        tx.commit().await?;
        if reuse.rows_affected() > 0 {
            tracing::warn!("refresh token reusado; sessão revogada");
        }
        return Err(ApiError::unauthorized());
    };

    if Utc::now() - session.created_at > Duration::days(SESSION_MAX_DAYS) {
        sqlx::query("UPDATE sessions SET revoked_at = now() WHERE id = $1").bind(session.id).execute(&mut *tx).await?;
        tx.commit().await?;
        return Err(ApiError::unauthorized());
    }

    let (new_token, new_hash) = generate_token();
    sqlx::query(
        "UPDATE sessions SET refresh_hash = $2, previous_refresh_hash = $3, last_used_at = now(),
                expires_at = now() + make_interval(days => $4), ip = COALESCE($5, ip), user_agent = COALESCE($6, user_agent)
         WHERE id = $1",
    )
    .bind(session.id)
    .bind(&new_hash)
    .bind(&hash)
    .bind(REFRESH_TTL_DAYS as i32)
    .bind(client_ip(&headers))
    .bind(user_agent(&headers))
    .execute(&mut *tx)
    .await?;
    let u = sqlx::query_as::<_, User>("SELECT id, email, name FROM users WHERE id = $1").bind(session.user_id).fetch_one(&mut *tx).await?;
    tx.commit().await?;
    Ok(Json(tokens_for(&s, u, session.id, new_token)?))
}

/// Revoga a sessão do JWT atual (o refresh dela morre junto).
pub async fn logout(State(s): State<AppState>, auth: Auth) -> Result<StatusCode, ApiError> {
    sqlx::query("UPDATE sessions SET revoked_at = now() WHERE id = $1 AND user_id = $2").bind(auth.session_id).bind(auth.user_id).execute(&s.pool).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// Derruba todas as sessões do usuário (todos os aparelhos).
pub async fn logout_all(State(s): State<AppState>, auth: Auth) -> Result<StatusCode, ApiError> {
    sqlx::query("UPDATE sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL").bind(auth.user_id).execute(&s.pool).await?;
    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------- /me

#[derive(Serialize)]
pub struct Me {
    pub user: User,
}

pub async fn me(State(s): State<AppState>, auth: Auth) -> Result<Json<Me>, ApiError> {
    let user = sqlx::query_as::<_, User>("SELECT id, email, name FROM users WHERE id = $1").bind(auth.user_id).fetch_one(&s.pool).await?;
    Ok(Json(Me { user }))
}

#[derive(Deserialize)]
pub struct PatchMe {
    name: Option<String>,
}

pub async fn patch_me(State(s): State<AppState>, auth: Auth, Json(b): Json<PatchMe>) -> Result<Json<User>, ApiError> {
    let name = match b.name {
        Some(n) => {
            let n = n.trim();
            if n.chars().count() > 80 || n.chars().any(char::is_control) {
                return Err(err(StatusCode::BAD_REQUEST, "nome: até 80 caracteres, sem quebra de linha"));
            }
            Some(n.to_string())
        }
        None => None,
    };
    let u = sqlx::query_as::<_, User>("UPDATE users SET name = COALESCE($2, name) WHERE id = $1 RETURNING id, email, name")
        .bind(auth.user_id)
        .bind(name)
        .fetch_one(&s.pool)
        .await?;
    Ok(Json(u))
}

/// Apaga a conta de quem chama; sessões e dados vão junto (ON DELETE CASCADE).
pub async fn delete_me(State(s): State<AppState>, auth: Auth) -> Result<StatusCode, ApiError> {
    sqlx::query("DELETE FROM users WHERE id = $1").bind(auth.user_id).execute(&s.pool).await?;
    tracing::info!(user = %auth.user_id, "conta apagada");
    Ok(StatusCode::NO_CONTENT)
}

/// Faxina periódica: magic links vencidos e sessões mortas há mais de 30 dias.
pub async fn cleanup(db: &PgPool) -> anyhow::Result<()> {
    sqlx::query("DELETE FROM magic_links WHERE expires_at < now() - interval '1 day'").execute(db).await?;
    sqlx::query(
        "DELETE FROM sessions WHERE (revoked_at IS NOT NULL AND revoked_at < now() - interval '30 days')
                                 OR expires_at < now() - interval '30 days'",
    )
    .execute(db)
    .await?;
    Ok(())
}
