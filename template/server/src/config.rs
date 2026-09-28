//! O que vem do ambiente, lido uma vez no boot. Falha cedo e alto se faltar algo obrigatório
//! ou fraco: melhor não subir do que subir inseguro.

use anyhow::{Context, bail};

#[derive(Clone)]
pub struct Config {
    /// Segredo do JWT de acesso (HS256). No mínimo 32 bytes.
    pub jwt_secret: Vec<u8>,
    /// Origem pública do app, sem barra no fim. Vai no link do email (`/entrar`), que abre o app
    /// web ou, no Android, o app instalado.
    pub app_base_url: String,
    pub mail_from: String,
    pub mail_from_name: String,
    /// Serviço de email (jmail): base da API e a chave deste app.
    pub jmail_url: String,
    pub jmail_api_key: String,
    /// Entrar com Google e com Discord (`oauth.rs`): cliente e segredo de cada um. Sem o par, o
    /// botão do provedor não aparece.
    pub google: Option<crate::oauth::OAuthClient>,
    pub discord: Option<crate::oauth::OAuthClient>,
    /// A conta de demonstração que entra por código (quem revisa o app na Play Store não recebe
    /// o email do magic link): `REVIEW_EMAIL` e `REVIEW_CODE`, os dois ou nenhum.
    pub review: Option<(String, String)>,
}

/// Cliente OAuth de `{PREFIX}_CLIENT_ID` e `{PREFIX}_CLIENT_SECRET`: os dois, ou nenhum.
fn oauth_client(prefix: &str) -> anyhow::Result<Option<crate::oauth::OAuthClient>> {
    match (var(&format!("{prefix}_CLIENT_ID")), var(&format!("{prefix}_CLIENT_SECRET"))) {
        (Some(id), Some(secret)) => Ok(Some(crate::oauth::OAuthClient { id, secret })),
        (None, None) => Ok(None),
        _ => bail!("{prefix}_CLIENT_ID e {prefix}_CLIENT_SECRET vão juntos"),
    }
}

fn var(k: &str) -> Option<String> {
    std::env::var(k).ok().map(|v| v.trim().to_string()).filter(|v| !v.is_empty())
}

impl Config {
    pub fn from_env() -> anyhow::Result<Self> {
        let jwt_secret = var("JWT_SECRET").context("falta JWT_SECRET")?;
        if jwt_secret.len() < 32 {
            bail!("JWT_SECRET precisa de pelo menos 32 caracteres (gere com `openssl rand -base64 48`)");
        }
        let jmail_api_key = var("JMAIL_API_KEY").context("falta JMAIL_API_KEY (chave do app {= name =} no jmail)")?;
        let trim = |s: String| s.trim_end_matches('/').to_string();
        Ok(Config {
            jwt_secret: jwt_secret.into_bytes(),
            app_base_url: trim(var("APP_BASE_URL").unwrap_or_else(|| "http://localhost:8080".into())),
            mail_from: var("MAIL_FROM").unwrap_or_else(|| "no-reply@{= name =}.local".into()),
            mail_from_name: var("MAIL_FROM_NAME").unwrap_or_else(|| "{= display_name =}".into()),
            jmail_url: trim(var("JMAIL_URL").unwrap_or_else(|| "http://127.0.0.1:8790".into())),
            jmail_api_key,
            google: oauth_client("GOOGLE")?,
            discord: oauth_client("DISCORD")?,
            review: match (var("REVIEW_EMAIL"), var("REVIEW_CODE")) {
                (Some(e), Some(c)) if c.len() >= 24 => Some((e.to_lowercase(), c)),
                (None, None) => None,
                _ => bail!("REVIEW_EMAIL e REVIEW_CODE vão juntos, e o código com pelo menos 24 caracteres"),
            },
        })
    }
}
