//! Envio de email pelo **jmail**, o serviço de entrega próprio (repo irmão em
//! /Volumes/Projects/jmail). A API dele espelha o `POST /v3/mail/send` do SendGrid, então o
//! corpo aqui é o formato do SendGrid v3: se o serviço de email mudar, só este arquivo muda.

use serde::Serialize;
use std::time::Duration;

#[derive(Serialize, Clone, Debug)]
pub struct EmailAddr {
    pub email: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
}

#[derive(Serialize, Clone, Debug)]
struct Personalization {
    to: Vec<EmailAddr>,
}

#[derive(Serialize, Clone, Debug)]
struct Content {
    /// "text/plain" ou "text/html"
    r#type: String,
    value: String,
}

/// Espelho do Mail Send do SendGrid v3, que o jmail aceita.
#[derive(Serialize, Clone, Debug)]
pub struct Mail {
    personalizations: Vec<Personalization>,
    from: EmailAddr,
    subject: String,
    content: Vec<Content>,
}

impl Mail {
    /// Mensagem com texto e HTML para um destinatário.
    pub fn simple(from: EmailAddr, to: &str, subject: &str, text: String, html: String) -> Self {
        Mail {
            personalizations: vec![Personalization { to: vec![EmailAddr { email: to.to_string(), name: None }] }],
            from,
            subject: subject.to_string(),
            content: vec![Content { r#type: "text/plain".into(), value: text }, Content { r#type: "text/html".into(), value: html }],
        }
    }
}

pub struct Mailer {
    base_url: String,
    api_key: String,
    http: reqwest::Client,
}

impl Mailer {
    pub fn new(base_url: &str, api_key: &str) -> anyhow::Result<Self> {
        Ok(Mailer {
            base_url: base_url.trim_end_matches('/').to_string(),
            api_key: api_key.to_string(),
            http: reqwest::Client::builder().timeout(Duration::from_secs(10)).connect_timeout(Duration::from_secs(3)).build()?,
        })
    }

    pub async fn send(&self, mail: Mail) -> anyhow::Result<()> {
        let to = mail.personalizations.first().and_then(|p| p.to.first()).map(|a| mask_email(&a.email)).unwrap_or_default();
        let r = self.http.post(format!("{}/v3/mail/send", self.base_url)).bearer_auth(&self.api_key).json(&mail).send().await?;
        let status = r.status();
        if !status.is_success() {
            // o corpo de erro do jmail não traz nada do email; seguro para o log
            let body = r.text().await.unwrap_or_default();
            anyhow::bail!("jmail respondeu {status}: {}", body.chars().take(300).collect::<String>());
        }
        tracing::info!(to = %to, subject = %mail.subject, "email aceito pelo jmail");
        Ok(())
    }
}

/// "joao@example.com" -> "j***@example.com": reconhecível no log sem expor o endereço.
pub fn mask_email(email: &str) -> String {
    match email.split_once('@') {
        Some((u, d)) => format!("{}***@{d}", u.chars().next().unwrap_or('*')),
        None => "***".into(),
    }
}

pub fn escape_html(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;").replace('\'', "&#39;")
}

/// Corpo HTML dos emails: um parágrafo de abertura, o botão e a letra miúda.
pub fn button_html(intro_html: &str, href: &str, label: &str, fine_print: &str) -> String {
    format!(
        "<div style=\"font-family:-apple-system,Roboto,Segoe UI,sans-serif;font-size:15px;color:#111;line-height:1.5\">\
         {intro_html}\
         <p><a href=\"{href}\" style=\"display:inline-block;padding:12px 20px;background:#{= colors.accent_dark =};color:#fff;\
         border-radius:10px;text-decoration:none;font-weight:700\">{label}</a></p>\
         <p style=\"color:#666;font-size:13px\">{fine_print}</p></div>",
        href = escape_html(href),
        label = escape_html(label),
        fine_print = escape_html(fine_print),
    )
}
