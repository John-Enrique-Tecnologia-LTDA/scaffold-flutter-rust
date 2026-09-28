#!/bin/sh
# Recompila o CLI (com template/ e skill/ embutidos) para todas as plataformas e grava em bin/:
#   scaffold-macos-arm64, scaffold-macos-x64, scaffold-linux-x64, scaffold-linux-arm64 (estáticos,
#   musl) e scaffold-windows-x64.exe. O ./scaffold (e scaffold.cmd no Windows) escolhe o certo.
#
# Precisa de zig e cargo-zigbuild (brew install zig && cargo install cargo-zigbuild --locked) e dos
# targets do rustup (o script adiciona os que faltarem). `./build.sh local` compila só o da máquina.
set -e
cd "$(dirname "$0")"
mkdir -p bin
M=cli/Cargo.toml
out() { cp "cli/target/$1/release/scaffold$3" "bin/scaffold-$2$3"; echo "· bin/scaffold-$2$3"; }

if [ "$1" = "local" ]; then
  cargo build --release --manifest-path $M
  case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) p=macos-arm64 ;; Darwin-x86_64) p=macos-x64 ;;
    Linux-x86_64) p=linux-x64 ;; Linux-aarch64|Linux-arm64) p=linux-arm64 ;;
    *) echo "plataforma sem nome em bin/: $(uname -sm)" >&2; exit 1 ;;
  esac
  cp cli/target/release/scaffold "bin/scaffold-$p"; echo "· bin/scaffold-$p"
  exit 0
fi

rustup target add aarch64-apple-darwin x86_64-apple-darwin x86_64-unknown-linux-musl aarch64-unknown-linux-musl x86_64-pc-windows-gnu >/dev/null
cargo zigbuild --release --manifest-path $M --target aarch64-apple-darwin && out aarch64-apple-darwin macos-arm64
cargo zigbuild --release --manifest-path $M --target x86_64-apple-darwin && out x86_64-apple-darwin macos-x64
cargo zigbuild --release --manifest-path $M --target x86_64-unknown-linux-musl && out x86_64-unknown-linux-musl linux-x64
cargo zigbuild --release --manifest-path $M --target aarch64-unknown-linux-musl && out aarch64-unknown-linux-musl linux-arm64
cargo zigbuild --release --manifest-path $M --target x86_64-pc-windows-gnu && out x86_64-pc-windows-gnu windows-x64 .exe
echo "binários atualizados em bin/"
