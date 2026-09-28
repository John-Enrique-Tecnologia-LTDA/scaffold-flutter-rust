#!/bin/sh
# Backend com hot-patch (Subsecond): editar o corpo de uma função em server/src e salvar aplica a
# mudança no processo que já está rodando, sem reiniciar. Mudou struct, enum ou assinatura? Aperte
# `r` no terminal do dx para um rebuild completo.
#
# Precisa do dioxus-cli 0.7.10 (`cargo install dioxus-cli --version 0.7.10 --locked`). O caminho é
# absoluto porque o `dx` do Deno (Homebrew) costuma vir antes no PATH; DX aponta outro binário.
set -e
DX="${DX:-$HOME/.cargo/bin/dx}"
if ! "$DX" --version 2>/dev/null | grep -q '^dioxus 0\.7\.'; then
  echo "dioxus-cli 0.7.x não encontrado em $DX (instale com: cargo install dioxus-cli --version 0.7.10 --locked)" >&2
  exit 1
fi
cd "$(dirname "$0")/server"
# o devserver do dx escuta na 8080 por padrão, a mesma porta da API: ele vai para a 8090
exec "$DX" serve --hot-patch --features hot --port "${DX_PORT:-8090}" "$@"
