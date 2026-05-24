#!/bin/bash
# Build easytier-core + easytier-web for x86_64 linux (C server deployment)
# Runs cross-compilation inside Docker from Mac host
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$PROJECT_DIR/vendor/EasyTier"
DIST_DIR="$PROJECT_DIR/dist/x86_64"

mkdir -p "$DIST_DIR"

echo "=== Building EasyTier for x86_64-unknown-linux-musl ==="

docker run --rm \
  -v "$VENDOR_DIR":/src \
  -v "${DIST_DIR}":/dist \
  -w /src \
  --platform linux/amd64 \
  rust:latest \
  bash -c '
    set -eu

    # Install musl toolchain
    apt-get update -qq && apt-get install -y -qq musl-tools pkg-config protobuf-compiler >/dev/null 2>&1
    rustup target add x86_64-unknown-linux-musl

    # Build frontend first
    if [ -d easytier-web/frontend ]; then
      echo "--- Building frontend ---"
      curl -fsSL https://get.pnpm.io/install.sh | bash - >/dev/null 2>&1
      export PATH="$HOME/.local/share/pnpm:$PATH"
      cd easytier-web/frontend
      pnpm install --frozen-lockfile 2>/dev/null || pnpm install
      pnpm build
      cd /src
    fi

    # Build easytier-core
    echo "--- Building easytier-core ---"
    cargo build --release --target x86_64-unknown-linux-musl -p easytier

    # Build easytier-web
    echo "--- Building easytier-web ---"
    cargo build --release --target x86_64-unknown-linux-musl -p easytier-web

    # Copy outputs
    cp target/x86_64-unknown-linux-musl/release/easytier-core /dist/ 2>/dev/null || \
    cp target/x86_64-unknown-linux-musl/release/easytier /dist/easytier-core
    cp target/x86_64-unknown-linux-musl/release/easytier-web /dist/

    echo "--- Done ---"
    ls -lh /dist/
  '

echo "=== Server binaries ready in $DIST_DIR ==="
ls -lh "$DIST_DIR"
