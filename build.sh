#!/bin/sh
# Recompila o CLI (com o template/ embutido) e deixa o binário ./scaffold na raiz.
set -e
cd "$(dirname "$0")"
cargo build --release --manifest-path cli/Cargo.toml
cp cli/target/release/scaffold ./scaffold
echo "./scaffold atualizado"
