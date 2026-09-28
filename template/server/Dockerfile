# Build do backend Rust em duas etapas: compila com a toolchain completa, roda numa imagem enxuta
# só com as bibliotecas de sistema necessárias. O contexto é a raiz do repositório (workspace):
#   docker build -f server/Dockerfile .
FROM rust:1-bookworm AS build
WORKDIR /src

# As dependências entram numa camada própria, para o cache sobreviver a mudanças no código.
COPY Cargo.toml Cargo.lock ./
COPY server/Cargo.toml server/Cargo.toml
RUN mkdir server/src && echo 'fn main() {}' > server/src/main.rs \
    && cargo build --profile server -p {= crate =} && rm -rf server/src

COPY server/src server/src
RUN touch server/src/main.rs && cargo build --profile server -p {= crate =}

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libssl3 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /src/target/server/{= crate =} /usr/local/bin/{= crate =}
COPY server/schema.sql ./schema.sql
# sem root no container: um bug no servidor não vira root no host
RUN useradd --system --no-create-home --shell /usr/sbin/nologin {= name =}
USER {= name =}

ENV PORT=8080
EXPOSE 8080
CMD ["{= crate =}"]
