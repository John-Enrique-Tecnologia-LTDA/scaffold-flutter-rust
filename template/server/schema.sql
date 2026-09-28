-- Schema do {= display_name =} em Postgres.
--
-- Contas são só email, com entrada por magic link, Google ou Discord (o email verificado do
-- provedor é a conta). O domínio (as entidades do manifest) é da conta
-- e é lido pelo SeaORM (server/src/entities). Não há migrations automáticas: mudança de schema é
-- editar este arquivo e escrever um script idempotente em db/migrations/ para rodar à mão em
-- produção.

-- ---------------------------------------------------------------- contas
CREATE TABLE users (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  email         TEXT        NOT NULL,
  name          TEXT        NOT NULL DEFAULT '',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_login_at TIMESTAMPTZ,
  -- bloqueada: não entra e as sessões não valem
  disabled_at   TIMESTAMPTZ
);
CREATE UNIQUE INDEX users_email_unq ON users (lower(email));

-- Magic link: só o hash do token vai para o banco. Uso único, vida curta.
CREATE TABLE magic_links (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  email      TEXT        NOT NULL,
  token_hash BYTEA       NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at    TIMESTAMPTZ,
  ip         TEXT,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX magic_links_email_created ON magic_links (lower(email), created_at DESC);
CREATE INDEX magic_links_ip_created    ON magic_links (ip, created_at DESC);

-- Entrar com Google e com Discord (oauth.rs): o estado de cada entrada em andamento (10 min) e a
-- entrada pronta que o app troca por uma sessão (2 min), as duas de uso único e presas ao desafio
-- do app (SHA-256 de um segredo dele).
CREATE TABLE oauth_states (
  state_hash    BYTEA       PRIMARY KEY,
  provider      TEXT        NOT NULL CHECK (provider IN ('google', 'discord')),
  platform      TEXT        NOT NULL CHECK (platform IN ('web', 'android', 'discord-app')),
  challenge     TEXT        NOT NULL,
  pkce_verifier TEXT        NOT NULL,
  ip            TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at    TIMESTAMPTZ NOT NULL
);
CREATE INDEX oauth_states_ip_created ON oauth_states (ip, created_at DESC);

CREATE TABLE oauth_grants (
  token_hash BYTEA       PRIMARY KEY,
  provider   TEXT        NOT NULL CHECK (provider IN ('google', 'discord')),
  email      TEXT        NOT NULL,
  name       TEXT        NOT NULL DEFAULT '',
  challenge  TEXT        NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  used_at    TIMESTAMPTZ
);

-- Sessão = um refresh token opaco (hash) que gira a cada uso. O hash anterior fica guardado
-- para detectar reuso: um token velho apresentado de novo vazou, e a sessão inteira cai.
CREATE TABLE sessions (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  refresh_hash          BYTEA       NOT NULL UNIQUE,
  previous_refresh_hash BYTEA,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at            TIMESTAMPTZ NOT NULL,
  revoked_at            TIMESTAMPTZ,
  ip                    TEXT,
  user_agent            TEXT
);
CREATE INDEX sessions_user ON sessions (user_id);
CREATE INDEX sessions_previous_hash ON sessions (previous_refresh_hash) WHERE previous_refresh_hash IS NOT NULL;

-- ---------------------------------------------------------------- domínio
{% for e in entities %}
-- {= e.label_plural =}
CREATE TABLE {= e.plural =} (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id   UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
{% for f in e.fields %}  {= f.name =} {= f.sql =},
{% endfor %}  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX {= e.plural =}_owner_updated ON {= e.plural =} (owner_id, updated_at DESC);
{% endfor %}